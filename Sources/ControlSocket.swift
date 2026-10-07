import Foundation
import Darwin

struct ControlResponse: Codable {
    let ok: Bool
    let message: String
    let status: PowerStatus?
}

func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    let bytes = Array(path.utf8) + [UInt8(0)]
    guard !path.contains("\0"), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw PowerModeError("控制接口路径过长。")
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: bytes)
    }
    return address
}

func configureSocket(_ fd: Int32) {
    var enabled: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
}

final class ControlServer {
    private let path: String
    private let allowedUID: uid_t
    private let handler: (String) -> ControlResponse
    private var source: DispatchSourceRead?
    private var clients: [Int32: (source: DispatchSourceRead, data: Data)] = [:]

    init(path: String, allowedUID: uid_t, handler: @escaping (String) -> ControlResponse) {
        self.path = path
        self.allowedUID = allowedUID
        self.handler = handler
    }

    func start() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PowerModeError("无法创建本地控制接口。") }
        var started = false
        defer { if !started { close(fd) } }
        configureSocket(fd)
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw PowerModeError("无法配置控制接口。") }
        var address = try socketAddress(path)
        _ = unlink(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, chown(path, allowedUID, gid_t.max) == 0,
              chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            let failure = errno
            _ = unlink(path)
            throw PowerModeError("无法建立控制接口：\(failure)。")
        }
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        reader.setEventHandler { [weak self] in self?.acceptClients(fd) }
        reader.setCancelHandler { close(fd) }
        source = reader
        started = true
        reader.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        for client in clients.values { client.source.cancel() }
        clients.removeAll()
        _ = unlink(path)
    }

    private func acceptClients(_ listener: Int32) {
        while true {
            let fd = accept(listener, nil, nil)
            if fd < 0 { return }
            var user: uid_t = 0
            var group: gid_t = 0
            guard getpeereid(fd, &user, &group) == 0,
                  user == allowedUID || user == 0,
                  clients.count < 16 else { close(fd); continue }
            configureSocket(fd)
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { close(fd); continue }
            let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            reader.setEventHandler { [weak self] in self?.readClient(fd) }
            reader.setCancelHandler { close(fd) }
            clients[fd] = (reader, Data())
            reader.resume()
        }
    }

    private func readClient(_ fd: Int32) {
        guard var client = clients[fd] else { return }
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = recv(fd, &buffer, buffer.count, 0)
        if count < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return }
        if count > 0 { client.data.append(contentsOf: buffer.prefix(count)) }
        clients[fd] = client
        if client.data.count > 32 {
            reply(fd, ControlResponse(ok: false, message: "指令过长。", status: nil))
        } else if client.data.contains(10) || count <= 0 {
            let command = String(decoding: client.data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            reply(fd, handler(command))
        }
    }

    private func reply(_ fd: Int32, _ response: ControlResponse) {
        if let data = try? JSONEncoder().encode(response) {
            data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                    if count < 0, errno == EINTR { continue }
                    if count <= 0 { break }
                    offset += count
                }
            }
        }
        clients.removeValue(forKey: fd)?.source.cancel()
    }
}

func sendControlCommand(_ command: String, path: String, expectedServerUID: uid_t = 0) throws -> ControlResponse {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw PowerModeError("无法创建控制连接。") }
    defer { close(fd) }
    configureSocket(fd)
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = try socketAddress(path)
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        throw PowerModeError("无法连接后台程序。首次使用请打开 MacAlwaysOn.app 并点击“安装服务”；已安装则检查 launchctl 状态。")
    }
    var user: uid_t = 0
    var group: gid_t = 0
    guard getpeereid(fd, &user, &group) == 0, user == expectedServerUID else {
        throw PowerModeError("后台程序的身份不正确，已拒绝发送指令。")
    }
    let request = Data((command + "\n").utf8)
    try request.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw PowerModeError("发送指令失败，请先查看实际状态再重试。") }
            offset += count
        }
    }
    _ = shutdown(fd, SHUT_WR)
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = recv(fd, &buffer, buffer.count, 0)
        if count < 0, errno == EINTR { continue }
        guard count >= 0 else { throw PowerModeError("未收到完整结果；指令可能已生效，请先查看状态。") }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
        guard data.count <= 65536 else { throw PowerModeError("后台程序返回了异常数据。") }
    }
    return try JSONDecoder().decode(ControlResponse.self, from: data)
}

func handleCommand(_ command: String, controller: PowerController) -> ControlResponse {
    do {
        switch command {
        case "on": try controller.enable()
        case "off": try controller.disable()
        case "toggle":
            if controller.isEnabled { try controller.disable() } else { try controller.enable() }
        case "status": break
        default: throw PowerModeError("只接受 on、off、toggle、status 指令。")
        }
        let status = try controller.status()
        return ControlResponse(ok: true, message: status.lastEvent, status: status)
    } catch {
        return ControlResponse(ok: false, message: String(describing: error), status: try? controller.status())
    }
}
