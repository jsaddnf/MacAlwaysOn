import Foundation
import Darwin

struct PowerModeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct PowerEnvironment: Codable {
    let source: String
    let thermal: String
    let batteryPercent: Int?

    var refusalReason: String? {
        guard source == "AC Power" else { return "当前未确认由外接电源供电。" }
        guard thermal == "nominal" || thermal == "fair" else {
            return "系统温控状态为 \(thermal)，不允许继续禁止睡眠。"
        }
        if let batteryPercent, batteryPercent <= 20 {
            return "电池电量不超过 20%，不允许继续禁止睡眠。"
        }
        return nil
    }
}

struct PowerSession: Codable {
    let version: Int
    let originalSleepDisabled: Bool
    let startedAt: Date

    init(originalSleepDisabled: Bool) {
        version = 1
        self.originalSleepDisabled = originalSleepDisabled
        startedAt = Date()
    }
}

protocol PowerBackend {
    func readSleepDisabled() throws -> Bool
    func writeSleepDisabled(_ disabled: Bool) throws
    func environment() -> PowerEnvironment
}

protocol SessionStore {
    func load() throws -> PowerSession?
    func save(_ session: PowerSession) throws
    func remove() throws
}

struct PowerStatus: Codable {
    let modeEnabled: Bool
    let systemSleepDisabled: Bool
    let environment: PowerEnvironment
    let startedAt: Date?
    let lastEvent: String
}

final class PowerController {
    private let backend: PowerBackend
    private let store: SessionStore
    private var session: PowerSession?
    private(set) var lastEvent = "后台程序已启动，远程运行模式尚未开启。"

    init(backend: PowerBackend, store: SessionStore) throws {
        self.backend = backend
        self.store = store
        session = try store.load()
        if let session, session.version != 1 || session.originalSleepDisabled {
            throw PowerModeError("保存的恢复记录无效；保留记录，请先检查，不能覆盖。")
        }
    }

    var isEnabled: Bool { session != nil }

    func recoverAtStartup() throws {
        if session != nil {
            try disable(reason: "检测到上次运行的记录，已恢复原来的睡眠设置。")
        }
    }

    func enable() throws {
        if let reason = backend.environment().refusalReason {
            if session != nil { try disable(reason: reason + " 已恢复原设置。") }
            throw PowerModeError(reason)
        }
        let current = try backend.readSleepDisabled()
        if session != nil {
            guard current else {
                try disable(reason: "其他程序已恢复系统睡眠；本程序已退出远程运行模式。")
                throw PowerModeError(lastEvent)
            }
            return
        }
        guard !current else {
            throw PowerModeError("系统已被其他工具设置为禁止睡眠。本程序不会接管或覆盖，请先关闭原来的工具。")
        }
        let newSession = PowerSession(originalSleepDisabled: current)
        try store.save(newSession)
        session = newSession
        do {
            try backend.writeSleepDisabled(true)
            guard try backend.readSleepDisabled() else {
                throw PowerModeError("系统未确认禁止睡眠已经生效。")
            }
            if let reason = backend.environment().refusalReason { throw PowerModeError(reason) }
            lastEvent = "远程运行模式已开启。关闭模式或拔掉电源后将恢复原设置。"
        } catch {
            let originalError = error
            do {
                try disable(reason: "开启失败，已恢复原设置。")
            } catch {
                throw PowerModeError("开启失败：\(originalError)；恢复也失败：\(error)。恢复记录已保留，请立即检查状态。")
            }
            throw originalError
        }
    }

    func disable(reason: String = "远程运行模式已关闭，已恢复原来的睡眠设置。") throws {
        guard let session else { return }
        if try backend.readSleepDisabled() != session.originalSleepDisabled {
            try backend.writeSleepDisabled(session.originalSleepDisabled)
        }
        guard try backend.readSleepDisabled() == session.originalSleepDisabled else {
            throw PowerModeError("恢复设置后校验失败；恢复记录仍保留，不能报告已关闭。")
        }
        try store.remove()
        self.session = nil
        lastEvent = reason
    }

    func environmentChanged() throws {
        if session != nil, let reason = backend.environment().refusalReason {
            try disable(reason: reason + " 远程运行模式已自动关闭。")
        }
    }

    func status() throws -> PowerStatus {
        PowerStatus(modeEnabled: isEnabled,
                    systemSleepDisabled: try backend.readSleepDisabled(),
                    environment: backend.environment(),
                    startedAt: session?.startedAt,
                    lastEvent: lastEvent)
    }
}

final class FileSessionStore: SessionStore {
    private let path: String
    private let owner: uid_t

    init(path: String, owner: uid_t) {
        self.path = path
        self.owner = owner
    }

    func load() throws -> PowerSession? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw PowerModeError("无法安全读取恢复记录：\(errno)。") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              info.st_size > 0, info.st_size <= 4096 else {
            throw PowerModeError("恢复记录的所有者、权限或大小不符合要求。")
        }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        return try JSONDecoder().decode(PowerSession.self, from: data)
    }

    func save(_ session: PowerSession) throws {
        let data = try JSONEncoder().encode(session)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        guard chmod(path, 0o600) == 0 else { throw PowerModeError("无法设置恢复记录权限。") }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw PowerModeError("无法同步恢复记录。") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw PowerModeError("无法将恢复记录写入磁盘。") }
        try syncDirectory()
    }

    func remove() throws {
        guard unlink(path) == 0 || errno == ENOENT else {
            throw PowerModeError("系统设置已恢复，但恢复记录暂时无法删除。")
        }
        try syncDirectory()
    }

    private func syncDirectory() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let fd = open(directory, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw PowerModeError("无法打开恢复记录目录。") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw PowerModeError("无法同步恢复记录目录。") }
    }
}
