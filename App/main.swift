import AppKit
import SwiftUI

private let installedHelper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.halo.remote-power")

enum AppAction: String, Sendable {
    case install, uninstall, on, off, status, doctor

    var progressText: String {
        switch self {
        case .install: return "正在安装，请完成系统授权…"
        case .uninstall: return "正在恢复设置并卸载，请完成系统授权…"
        case .on: return "正在开启远程运行模式…"
        case .off: return "正在恢复原来的睡眠设置…"
        case .status: return "正在读取状态…"
        case .doctor: return "正在读取休眠诊断…"
        }
    }
}

struct ProcessResult: Sendable {
    let code: Int32
    let data: Data
    var text: String { String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct AppRunner: Sendable {
    let payload: URL

    func run(_ action: AppAction) -> ProcessResult {
        let executable: URL
        let arguments: [String]
        switch action {
        case .install, .uninstall:
            executable = URL(fileURLWithPath: "/bin/zsh")
            arguments = ["-f", payload.appendingPathComponent("run-ui.sh").path, action.rawValue]
        case .doctor:
            executable = payload.appendingPathComponent("bin/remote-power")
            arguments = ["doctor"]
        case .on, .off, .status:
            do {
                let response = try sendControlCommand(action.rawValue, path: "/private/var/run/com.halo.remote-power/control.sock")
                return ProcessResult(code: response.ok ? 0 : 1, data: try JSONEncoder().encode(response))
            } catch {
                return ProcessResult(code: 1, data: Data("\(error)".utf8))
            }
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ProcessResult(code: process.terminationStatus, data: data)
        } catch {
            return ProcessResult(code: 1, data: Data("无法执行操作：\(error.localizedDescription)".utf8))
        }
    }
}

enum ServiceState {
    case checking
    case missing
    case unavailable(String)
    case connected(PowerStatus)

    var snapshot: PowerStatus? {
        if case .connected(let snapshot) = self { return snapshot }
        return nil
    }

    var isInstalled: Bool {
        switch self {
        case .connected, .unavailable: return true
        case .checking, .missing: return false
        }
    }

    var title: String {
        switch self {
        case .checking: return "正在读取状态"
        case .missing: return "尚未安装后台服务"
        case .unavailable: return "暂时无法连接后台服务"
        case .connected(let snapshot): return snapshot.modeEnabled ? "远程运行已开启" : "远程运行已关闭"
        }
    }

    var detail: String {
        switch self {
        case .checking: return "请稍候。"
        case .missing: return "首次使用请点击下方“安装服务”，然后接通电源再开启。"
        case .unavailable(let message): return message
        case .connected(let snapshot): return snapshot.lastEvent
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var service: ServiceState = .checking
    @Published private(set) var pendingAction: AppAction?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var operationMessage = ""
    @Published private(set) var operationFailed = false
    @Published var showDiagnostics = false
    @Published private(set) var diagnostics = ""

    private let runner = AppRunner(payload: Bundle.main.resourceURL!.appendingPathComponent("Payload"))
    var isBusy: Bool { pendingAction != nil }
    var isChangingSystem: Bool {
        guard let action = pendingAction else { return false }
        return [.install, .uninstall, .on, .off].contains(action)
    }

    func perform(_ action: AppAction) {
        guard !isBusy else { return }
        pendingAction = action
        Task {
            defer { pendingAction = nil }
            if action == .status {
                await refreshState()
                return
            }
            let runner = self.runner
            let result = await Task.detached { runner.run(action) }.value
            if action == .doctor {
                diagnostics = result.text
                showDiagnostics = true
            } else if let response = try? JSONDecoder().decode(ControlResponse.self, from: result.data) {
                operationMessage = response.ok ? "" : response.message
                operationFailed = !response.ok
            } else {
                operationMessage = result.text
                operationFailed = result.code != 0
            }
            await refreshState()
        }
    }

    private func refreshState() async {
        guard FileManager.default.isExecutableFile(atPath: installedHelper.path) else {
            service = .missing
            lastRefresh = Date()
            return
        }
        let runner = self.runner
        let result = await Task.detached { runner.run(.status) }.value
        if let response = try? JSONDecoder().decode(ControlResponse.self, from: result.data),
           response.ok, let snapshot = response.status {
            service = .connected(snapshot)
        } else {
            service = .unavailable(result.text.isEmpty ? "没有收到状态，请点击“刷新状态”重试。" : result.text)
        }
        lastRefresh = Date()
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppModel.shared.isChangingSystem
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.isChangingSystem else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "操作尚未结束"
        alert.informativeText = "请等待当前操作完成，再退出 MacAlwaysOn。"
        alert.addButton(withTitle: "好")
        alert.runModal()
        return .terminateCancel
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var confirmUninstall = false
    private var snapshot: PowerStatus? { model.service.snapshot }
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacAlwaysOn").font(.title2.bold())
                    Text("接电保持唤醒，用完恢复睡眠").foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(version)").font(.caption).foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(model.service.title).font(.headline)
                        Spacer()
                        Button("刷新状态") { model.perform(.status) }
                            .disabled(model.isBusy)
                    }
                    if let snapshot {
                        HStack(spacing: 24) {
                            Label(powerText(snapshot.environment.source), systemImage: "powerplug")
                            if let battery = snapshot.environment.batteryPercent {
                                Label("\(battery)%", systemImage: "battery.100")
                            }
                            Label(thermalText(snapshot.environment.thermal), systemImage: "thermometer.medium")
                        }.font(.callout)
                        Text("系统禁止睡眠：\(snapshot.systemSleepDisabled ? "是" : "否")")
                            .font(.callout).foregroundStyle(.secondary)
                        if snapshot.modeEnabled != snapshot.systemSleepDisabled {
                            Text("本程序状态与系统设置不一致，请检查其他电源工具。")
                                .font(.callout).foregroundStyle(.orange)
                        }
                    }
                    Text(snapshot == nil ? model.service.detail : "最近事件：" + model.service.detail)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let time = model.lastRefresh {
                        Text("上次读取：\(time.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button { model.perform(.on) } label: {
                    Label("开启远程", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(model.isBusy || snapshot == nil || snapshot?.modeEnabled == true)
                Button { model.perform(.off) } label: {
                    Label("关闭远程", systemImage: "moon")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy || snapshot?.modeEnabled != true)
            }.controlSize(.large)

            if let action = model.pendingAction {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(action.progressText).font(.callout)
                }
            } else if !model.operationMessage.isEmpty {
                Text(model.operationMessage)
                    .font(.callout)
                    .foregroundStyle(model.operationFailed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Divider()
            HStack(spacing: 12) {
                Button(model.service.isInstalled ? "服务已安装" : "安装服务") { model.perform(.install) }
                    .disabled(model.isBusy || model.service.isInstalled)
                Button("检查休眠原因") { model.perform(.doctor) }.disabled(model.isBusy)
                Spacer()
                Button("卸载服务", role: .destructive) { confirmUninstall = true }
                    .disabled(model.isBusy || !model.service.isInstalled)
            }
            Text("安装和卸载需要管理员授权。关闭窗口不会关闭已开启的远程运行模式。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 550)
        .task { model.perform(.status) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.perform(.status)
        }
        .confirmationDialog("卸载后台服务？", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("恢复设置并卸载", role: .destructive) { model.perform(.uninstall) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将先恢复本程序修改的电源设置，再移除服务。合盖时可能进入睡眠并断开远程连接。")
        }
        .sheet(isPresented: $model.showDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("休眠诊断").font(.title2.bold())
                ScrollView {
                    Text(model.diagnostics)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("复制诊断") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.diagnostics, forType: .string)
                    }
                    Spacer()
                    Button("关闭") { model.showDiagnostics = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 680, height: 470)
        }
    }

    private func powerText(_ source: String) -> String {
        switch source {
        case "AC Power": return "已接电"
        case "Battery Power": return "电池供电"
        case "UPS Power": return "UPS 供电"
        default: return "供电未知"
        }
    }

    private func thermalText(_ thermal: String) -> String {
        switch thermal {
        case "nominal": return "温控正常"
        case "fair": return "温控轻度升高"
        case "serious": return "温控严重"
        case "critical": return "温控临界"
        default: return "温控未知"
        }
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(isEnabled ? Color.blue.opacity(configuration.isPressed ? 0.8 : 1) : Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

@main
struct MacAlwaysOnApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("MacAlwaysOn", id: "main") {
            MainView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
