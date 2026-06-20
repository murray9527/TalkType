import Foundation
import AppKit

// Checks system capabilities at launch and surfaces issues to the user.
struct CompatibilityChecker {

    struct Report {
        var warnings: [String] = []
        var suggestedModelID: String = "small"

        var hasWarnings: Bool { !warnings.isEmpty }
    }

    static func run() -> Report {
        var report = Report()

        // macOS version
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        if ver.majorVersion < 13 {
            report.warnings.append("macOS \(ver.majorVersion).\(ver.minorVersion) 可能存在兼容性问题，建议升级到 macOS 13+")
        }

        // Physical memory
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if ramGB < 4 {
            report.warnings.append("内存不足 4GB，建议使用 Small 模型")
            report.suggestedModelID = "small"
        } else if ramGB < 8 {
            report.suggestedModelID = "small"
        } else if ramGB < 16 {
            report.suggestedModelID = "small"
        } else {
            report.suggestedModelID = "medium"
        }

        // Apple Silicon vs Intel
        let isAppleSilicon = isRunningOnAppleSilicon()
        if !isAppleSilicon {
            report.warnings.append("Intel Mac 上 Whisper 推理较慢，建议使用 Small 模型")
        }

        // Disk space: check models directory free space
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: support.path),
           let free = attrs[.systemFreeSize] as? Int64, free < 600_000_000 {
            report.warnings.append("可用磁盘空间不足 600MB，下载模型前请清理磁盘")
        }

        return report
    }

    private static func isRunningOnAppleSilicon() -> Bool {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { ptr -> String in
            let bytes = ptr.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }
        return machine.hasPrefix("arm")
    }
}
