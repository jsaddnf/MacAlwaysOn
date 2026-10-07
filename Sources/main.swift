import Foundation
import IOKit.ps
import Darwin

let stateDirectory = "/Library/Application Support/RemotePower"
let runtimeDirectory = "/private/var/run/com.halo.remote-power"
let controlPath = runtimeDirectory + "/control.sock"
let statePath = stateDirectory + "/session.json"
var retainedServer: ControlServer?
var retainedSignals: [DispatchSourceSignal] = []
var retainedPowerNotification: CFRunLoopSource?
var retainedThermalObserver: NSObjectProtocol?
var retainedLock: Int32 = -1

func lockService() throws {
    retainedLock = open(stateDirectory + "/service.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard retainedLock >= 0, flock(retainedLock, LOCK_EX | LOCK_NB) == 0 else {
        throw PowerModeError("已有一个后台程序或恢复操作正在运行。")
    }
}

func logEvent(_ message: String) { NSLog("RemotePower: %@", message) }

func runDaemon(allowedUID: uid_t) throws -> Never {
    guard geteuid() == 0, allowedUID >= 501, getpwuid(allowedUID) != nil else {
        throw PowerModeError("后台程序必须由系统启动，且只能服务于安装时指定的普通用户。")
    }
    umask(0o077)
    try validateServiceDirectory(stateDirectory, owner: 0)
    try lockService()
    let controller = try PowerController(backend: MacPowerBackend(), store: FileSessionStore(path: statePath, owner: 0))
    try controller.recoverAtStartup()
    try prepareRuntimeDirectory(runtimeDirectory, owner: 0)

    let context = Unmanaged.passUnretained(controller).toOpaque()
    guard let notification = IOPSNotificationCreateRunLoopSource({ context in
        guard let context else { return }
        let controller = Unmanaged<PowerController>.fromOpaque(context).takeUnretainedValue()
        do {
            let wasEnabled = controller.isEnabled
            try controller.environmentChanged()
            if wasEnabled && !controller.isEnabled { logEvent(controller.lastEvent) }
        } catch {
            logEvent("供电变化后恢复失败，退出并让 launchd 重新启动恢复：\(error)")
            exit(1)
        }
    }, context)?.takeRetainedValue() else {
        throw PowerModeError("无法监听供电变化，拒绝启动保活功能。")
    }
    retainedPowerNotification = notification
    CFRunLoopAddSource(CFRunLoopGetMain(), notification, .commonModes)
    retainedThermalObserver = NotificationCenter.default.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
    ) { _ in
        do {
            let wasEnabled = controller.isEnabled
            try controller.environmentChanged()
            if wasEnabled && !controller.isEnabled { logEvent(controller.lastEvent) }
        } catch {
            logEvent("温控变化后恢复失败，退出并让 launchd 重新启动恢复：\(error)")
            exit(1)
        }
    }
    for number in [SIGTERM, SIGINT, SIGHUP] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            do {
                try controller.disable(reason: "后台程序退出，已恢复原设置。")
                logEvent(controller.lastEvent)
                retainedServer?.stop()
                exit(0)
            } catch {
                logEvent("退出前恢复失败；恢复记录已保留：\(error)")
                exit(1)
            }
        }
        retainedSignals.append(source)
        source.resume()
    }
    let server = ControlServer(path: controlPath, allowedUID: allowedUID) { command in
        let response = handleCommand(command, controller: controller)
        if command != "status" { logEvent(response.message) }
        if !response.ok && controller.isEnabled && ["on", "off", "toggle"].contains(command) {
            DispatchQueue.main.async {
                logEvent("操作失败且恢复记录仍存在，退出并让 launchd 重新启动恢复。")
                exit(1)
            }
        }
        return response
    }
    retainedServer = server
    try server.start()
    logEvent(controller.lastEvent)
    CFRunLoopRun()
    throw PowerModeError("系统事件循环意外结束。")
}

func printStatus(_ status: PowerStatus) {
    print("远程运行模式：\(status.modeEnabled ? "已开启" : "已关闭")")
    print("系统禁止睡眠：\(status.systemSleepDisabled ? "是" : "否")")
    print("供电：\(status.environment.source)，温控：\(status.environment.thermal)")
    if let battery = status.environment.batteryPercent { print("电池：\(battery)%") }
    if status.modeEnabled != status.systemSleepDisabled {
        print("注意：本程序状态与系统设置不一致，可能有其他电源工具正在修改设置。")
    }
    if !status.modeEnabled {
        print("关闭表示已撤销本程序的设置；其他应用仍可能阻止休眠。运行 doctor 可查看。")
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let command = arguments.first ?? "status"
    switch command {
    case "daemon":
        guard arguments.count == 2, let uid = uid_t(arguments[1]) else { throw PowerModeError("后台程序参数无效。") }
        try runDaemon(allowedUID: uid)
    case "recover":
        guard geteuid() == 0, arguments.count == 1 else { throw PowerModeError("恢复操作需要管理员权限。") }
        try validateServiceDirectory(stateDirectory, owner: 0)
        try lockService()
        let controller = try PowerController(backend: MacPowerBackend(), store: FileSessionStore(path: statePath, owner: 0))
        try controller.recoverAtStartup()
        print("本程序的恢复记录已处理。")
    case "doctor":
        guard arguments.count == 1 else { throw PowerModeError("doctor 不接受额外参数。") }
        if let response = try? sendControlCommand("status", path: controlPath), let status = response.status {
            printStatus(status)
            print(response.message)
        } else {
            print("后台程序未连接；以下为只读系统检查。")
        }
        for item in [("系统设置", ["-g"]), ("接电和电池设置", ["-g", "custom"]),
                     ("供电情况", ["-g", "batt"]), ("阻止睡眠的进程", ["-g", "assertions"]),
                     ("计划电源事件", ["-g", "sched"])] {
            print("\n\(item.0)：")
            print(try runCommand("/usr/bin/pmset", item.1), terminator: "")
        }
    case "on", "off", "toggle", "status":
        guard arguments.isEmpty || arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--json") else {
            throw PowerModeError("只支持可选参数 --json。")
        }
        let response = try sendControlCommand(command, path: controlPath)
        if arguments.last == "--json" {
            print(String(decoding: try JSONEncoder().encode(response), as: UTF8.self))
        } else {
            print(response.message)
            if let status = response.status { printStatus(status) }
        }
        if !response.ok { exit(1) }
    default:
        throw PowerModeError("用法：remote-power on | off | toggle | status | doctor")
    }
} catch {
    fputs("错误：\(error)\n", stderr)
    exit(1)
}
