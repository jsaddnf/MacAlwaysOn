import Foundation
import Darwin

let safeEnvironment = PowerEnvironment(source: "AC Power", thermal: "nominal", batteryPercent: 80)

final class Trace { var events: [String] = [] }

final class FakeBackend: PowerBackend {
    var disabled = false
    var currentEnvironment = safeEnvironment
    var writes: [Bool] = []
    var hook: ((Bool) throws -> Void)?
    let trace: Trace
    init(trace: Trace = Trace()) { self.trace = trace }
    func readSleepDisabled() throws -> Bool { disabled }
    func writeSleepDisabled(_ value: Bool) throws {
        trace.events.append("write:\(value)")
        writes.append(value)
        if let hook { try hook(value) } else { disabled = value }
    }
    func environment() -> PowerEnvironment { currentEnvironment }
}

final class MemoryStore: SessionStore {
    var session: PowerSession?
    var failSave = false
    var failRemove = false
    var saves = 0
    let trace: Trace
    init(trace: Trace = Trace()) { self.trace = trace }
    func load() throws -> PowerSession? { session }
    func save(_ value: PowerSession) throws {
        if failSave { throw PowerModeError("save failed") }
        trace.events.append("save")
        saves += 1
        session = value
    }
    func remove() throws {
        if failRemove { throw PowerModeError("remove failed") }
        trace.events.append("remove")
        session = nil
    }
}

final class DiskBackend: PowerBackend {
    let path: String
    init(path: String) { self.path = path }
    func readSleepDisabled() throws -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return try String(contentsOfFile: path, encoding: .utf8) == "1"
    }
    func writeSleepDisabled(_ value: Bool) throws {
        try (value ? "1" : "0").write(toFile: path, atomically: true, encoding: .utf8)
    }
    func environment() -> PowerEnvironment { safeEnvironment }
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "断言失败") throws {
    guard try condition() else { throw PowerModeError(message) }
}

func expectError(_ body: () throws -> Void) throws {
    var failed = false
    do { try body() } catch { failed = true }
    try expect(failed, "预期操作失败，但操作成功")
}

func fixture() throws -> (FakeBackend, MemoryStore, PowerController) {
    let trace = Trace()
    let backend = FakeBackend(trace: trace)
    let store = MemoryStore(trace: trace)
    return (backend, store, try PowerController(backend: backend, store: store))
}

func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("remote-power-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    return url
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--test-server" {
    do {
        let directory = CommandLine.arguments[2]
        let controller = try PowerController(backend: DiskBackend(path: directory + "/fake-setting"),
            store: FileSessionStore(path: directory + "/session.json", owner: getuid()))
        try controller.recoverAtStartup()
        let server = ControlServer(path: directory + "/control.sock", allowedUID: getuid()) {
            handleCommand($0, controller: controller)
        }
        try server.start()
        withExtendedLifetime(server) { dispatchMain() }
    } catch { fputs("测试服务失败：\(error)\n", stderr); exit(1) }
}

var failures = 0
var count = 0
func test(_ name: String, _ body: () throws -> Void) {
    count += 1
    do { try body(); print("PASS \(name)") }
    catch { failures += 1; print("FAIL \(name)：\(error)") }
}

test("首次启动不修改系统设置") {
    let (backend, _, controller) = try fixture()
    try controller.recoverAtStartup()
    try expect(backend.writes.isEmpty && !controller.isEnabled)
}
test("先保存恢复记录，再开启禁止睡眠") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    try expect(backend.trace.events == ["save", "write:true"])
    try expect(store.session?.originalSleepDisabled == false && backend.disabled)
}
test("重复开启不覆盖第一次保存的设置") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    let started = store.session?.startedAt
    try controller.enable()
    try expect(store.saves == 1 && backend.writes == [true] && store.session?.startedAt == started)
}
test("重复关闭不写入额外设置") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    try controller.disable()
    try controller.disable()
    try expect(backend.writes == [true, false] && store.session == nil && !controller.isEnabled)
}
test("不接管其他工具已经开启的全局禁止睡眠") {
    let (backend, store, controller) = try fixture()
    backend.disabled = true
    try expectError { try controller.enable() }
    try controller.disable()
    try expect(backend.disabled && backend.writes.isEmpty && store.session == nil)
}
for source in ["Battery Power", "UPS Power", "Unknown"] {
    test("拒绝在 \(source) 下开启") {
        let (backend, store, controller) = try fixture()
        backend.currentEnvironment = PowerEnvironment(source: source, thermal: "nominal", batteryPercent: 80)
        try expectError { try controller.enable() }
        try expect(store.session == nil && backend.writes.isEmpty)
    }
}
for thermal in ["serious", "critical", "unknown"] {
    test("拒绝在温控 \(thermal) 下开启") {
        let (backend, _, controller) = try fixture()
        backend.currentEnvironment = PowerEnvironment(source: "AC Power", thermal: thermal, batteryPercent: 80)
        try expectError { try controller.enable() }
        try expect(backend.writes.isEmpty)
    }
}
test("接电但电池过低时拒绝开启") {
    let (backend, _, controller) = try fixture()
    backend.currentEnvironment = PowerEnvironment(source: "AC Power", thermal: "nominal", batteryPercent: 20)
    try expectError { try controller.enable() }
    try expect(backend.writes.isEmpty)
}
test("拔电自动关闭，重新接电不会自动开启") {
    let (backend, _, controller) = try fixture()
    try controller.enable()
    backend.currentEnvironment = PowerEnvironment(source: "Battery Power", thermal: "nominal", batteryPercent: 80)
    try controller.environmentChanged()
    backend.currentEnvironment = safeEnvironment
    try controller.environmentChanged()
    try expect(!backend.disabled && !controller.isEnabled && backend.writes == [true, false])
}
test("温控恶化后自动关闭") {
    let (backend, _, controller) = try fixture()
    try controller.enable()
    backend.currentEnvironment = PowerEnvironment(source: "AC Power", thermal: "serious", batteryPercent: 80)
    try controller.environmentChanged()
    try expect(!backend.disabled && !controller.isEnabled)
}
test("恢复记录保存失败时不会修改电源") {
    let (backend, store, controller) = try fixture()
    store.failSave = true
    try expectError { try controller.enable() }
    try expect(backend.writes.isEmpty && !controller.isEnabled)
}
test("写入前报错，清理未生效的会话") {
    let (backend, store, controller) = try fixture()
    backend.hook = { _ in throw PowerModeError("write failed") }
    try expectError { try controller.enable() }
    try expect(!backend.disabled && store.session == nil && !controller.isEnabled)
}
test("写入已经生效但命令报错，仍恢复原设置") {
    let (backend, store, controller) = try fixture()
    backend.hook = { value in
        backend.disabled = value
        if value { throw PowerModeError("failed after write") }
    }
    try expectError { try controller.enable() }
    try expect(!backend.disabled && store.session == nil && backend.writes == [true, false])
}
test("命令返回成功但设置未生效，不报告开启成功") {
    let (backend, store, controller) = try fixture()
    backend.hook = { _ in }
    try expectError { try controller.enable() }
    try expect(!controller.isEnabled && store.session == nil)
}
test("开启过程中拔电，立即恢复") {
    let (backend, store, controller) = try fixture()
    backend.hook = { value in
        backend.disabled = value
        if value { backend.currentEnvironment = PowerEnvironment(source: "Battery Power", thermal: "nominal", batteryPercent: 80) }
    }
    try expectError { try controller.enable() }
    try expect(!backend.disabled && store.session == nil)
}
test("关闭写入失败保留恢复记录，重启后可恢复") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    backend.hook = { _ in throw PowerModeError("restore failed") }
    try expectError { try controller.disable() }
    try expect(backend.disabled && store.session != nil && controller.isEnabled)
    backend.hook = nil
    let restarted = try PowerController(backend: backend, store: store)
    try restarted.recoverAtStartup()
    try expect(!backend.disabled && store.session == nil && !restarted.isEnabled)
}
test("关闭写入未生效，不删除恢复记录") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    backend.hook = { _ in }
    try expectError { try controller.disable() }
    try expect(store.session != nil && backend.disabled)
}
test("设置已恢复但记录删除失败，重启可继续清理") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    store.failRemove = true
    try expectError { try controller.disable() }
    try expect(!backend.disabled && store.session != nil)
    store.failRemove = false
    let restarted = try PowerController(backend: backend, store: store)
    try restarted.recoverAtStartup()
    try expect(store.session == nil && backend.writes == [true, false])
}
test("其他程序恢复睡眠后，不自动重新禁止睡眠") {
    let (backend, store, controller) = try fixture()
    try controller.enable()
    backend.disabled = false
    try expectError { try controller.enable() }
    try expect(store.session == nil && backend.writes == [true])
}
test("开启失败且恢复失败，保留记录供下次恢复") {
    let (backend, store, controller) = try fixture()
    backend.hook = { value in
        if value { backend.disabled = true }
        throw PowerModeError("both writes failed")
    }
    try expectError { try controller.enable() }
    try expect(backend.disabled && store.session != nil)
}
test("未知协议指令不会修改电源") {
    let (backend, _, controller) = try fixture()
    let response = handleCommand("on\noff", controller: controller)
    try expect(!response.ok && backend.writes.isEmpty)
}
test("解析真实 pmset 格式并拒绝异常值") {
    try expect(!MacPowerBackend.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t0\n"))
    try expect(MacPowerBackend.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t1\n"))
    try expect(!MacPowerBackend.parseSleepDisabled("System-wide power settings:\n"))
    try expectError { _ = try MacPowerBackend.parseSleepDisabled("SleepDisabled 2") }
    try expectError { _ = try MacPowerBackend.parseSleepDisabled("") }
}
test("磁盘记录跨实例恢复且权限为 0600") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileSessionStore(path: directory.appendingPathComponent("session.json").path, owner: getuid())
    let backend = FakeBackend()
    let first = try PowerController(backend: backend, store: store)
    try first.enable()
    let restored = try PowerController(backend: backend, store: store)
    try restored.recoverAtStartup()
    try expect(!backend.disabled && !restored.isEnabled && store.load() == nil)
}
test("拒绝通过符号链接读取恢复记录") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("target").path
    let path = directory.appendingPathComponent("session.json").path
    try JSONEncoder().encode(PowerSession(originalSleepDisabled: false)).write(to: URL(fileURLWithPath: target))
    try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    let store = FileSessionStore(path: path, owner: getuid())
    try expectError { _ = try store.load() }
}
test("拒绝可被其他用户修改的恢复记录") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("session.json").path
    let store = FileSessionStore(path: path, owner: getuid())
    try store.save(PowerSession(originalSleepDisabled: false))
    _ = chmod(path, 0o666)
    try expectError { _ = try store.load() }
}

test("运行目录已存在时，重启不再因重复创建退出") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = directory.appendingPathComponent("runtime").path
    try prepareRuntimeDirectory(runtime, owner: getuid())
    try prepareRuntimeDirectory(runtime, owner: getuid())
    try validateServiceDirectory(runtime, owner: getuid())
}
test("拒绝符号链接或可被其他用户写入的运行目录") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = directory.appendingPathComponent("runtime").path
    try FileManager.default.createSymbolicLink(atPath: runtime, withDestinationPath: directory.path)
    try expectError { try prepareRuntimeDirectory(runtime, owner: getuid()) }
    try FileManager.default.removeItem(atPath: runtime)
    try prepareRuntimeDirectory(runtime, owner: getuid())
    _ = chmod(runtime, 0o777)
    try expectError { try prepareRuntimeDirectory(runtime, owner: getuid()) }
}

test("本地接口与真实子进程崩溃恢复，使用文件模拟电源设置") {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let socket = directory.appendingPathComponent("control.sock").path
    let readyPath = directory.appendingPathComponent("session.json").path
    var children: [Process] = []
    defer {
        for child in children where child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() }
    }
    func startServer() throws -> Process {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.arguments = ["--test-server", directory.path]
        child.standardOutput = FileHandle.nullDevice
        try child.run()
        children.append(child)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, child.isRunning {
            if let reply = try? sendControlCommand("status", path: socket, expectedServerUID: getuid()), reply.ok { return child }
            usleep(20_000)
        }
        throw PowerModeError("测试用本地接口未启动")
    }
    let first = try startServer()
    let started = try sendControlCommand("on", path: socket, expectedServerUID: getuid())
    try expect(started.ok && started.status?.modeEnabled == true)
    try expect(FileManager.default.fileExists(atPath: readyPath))
    let invalid = try sendControlCommand(String(repeating: "x", count: 64), path: socket, expectedServerUID: getuid())
    try expect(!invalid.ok)
    if getuid() != 0 { try expectError { _ = try sendControlCommand("off", path: socket) } }
    try expect(try sendControlCommand("status", path: socket, expectedServerUID: getuid()).status?.modeEnabled == true)
    kill(first.processIdentifier, SIGKILL)
    first.waitUntilExit()
    _ = try startServer()
    let recovered = try sendControlCommand("status", path: socket, expectedServerUID: getuid())
    try expect(recovered.ok && recovered.status?.systemSleepDisabled == false && recovered.status?.modeEnabled == false)
    try expect(!FileManager.default.fileExists(atPath: readyPath))
    try expect(try sendControlCommand("toggle", path: socket, expectedServerUID: getuid()).status?.modeEnabled == true)
    try expect(try sendControlCommand("toggle", path: socket, expectedServerUID: getuid()).status?.modeEnabled == false)
}

print("\n\(count - failures)/\(count) 项测试通过；测试未修改真实电源设置。")
exit(failures == 0 ? 0 : 1)
