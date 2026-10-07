import Foundation
import IOKit.ps

func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
        throw PowerModeError("\(URL(fileURLWithPath: executable).lastPathComponent) 执行失败：\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return output
}

struct MacPowerBackend: PowerBackend {
    static func parseSleepDisabled(_ output: String) throws -> Bool {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled" {
                guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else {
                    throw PowerModeError("无法识别系统 SleepDisabled 设置。")
                }
                return fields[1] == "1"
            }
        }
        guard output.contains("System-wide power settings:") else {
            throw PowerModeError("系统未返回可识别的电源设置。")
        }
        return false
    }

    func readSleepDisabled() throws -> Bool {
        try Self.parseSleepDisabled(runCommand("/usr/bin/pmset", ["-g"]))
    }

    func writeSleepDisabled(_ disabled: Bool) throws {
        _ = try runCommand("/usr/bin/pmset", ["disablesleep", disabled ? "1" : "0"])
    }

    func environment() -> PowerEnvironment {
        var source = "Unknown"
        var batteryPercent: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let value = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
                source = value as String
            }
            if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                for item in sources {
                    guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                          description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                          let current = description[kIOPSCurrentCapacityKey] as? Int,
                          let maximum = description[kIOPSMaxCapacityKey] as? Int,
                          maximum > 0 else { continue }
                    batteryPercent = min(100, max(0, current * 100 / maximum))
                    break
                }
            }
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return PowerEnvironment(source: source, thermal: thermal, batteryPercent: batteryPercent)
    }
}
