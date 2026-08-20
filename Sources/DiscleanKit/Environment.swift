import Foundation

/// 設定・状態ディレクトリと環境変数由来の設定をまとめた実行環境。
public struct DiscleanEnvironment: Sendable {
    public let home: String
    public let configDir: String
    public let stateDir: String
    public let osVersion: String
    public let osBuild: String
    public let arch: String
    public let isJapanese: Bool
    public let noColor: Bool

    public var quarantineDir: String { stateDir + "/quarantine" }
    public var auditDir: String { stateDir + "/audit" }
    public var cacheDir: String { stateDir + "/cache" }
    public var updatesDir: String { stateDir + "/updates" }
    public var rulesOverrideDir: String { configDir + "/rules.d" }
    public var configFile: String { configDir + "/config.json" }
    public var envFile: String { stateDir + "/env.json" }

    public init(processInfo: ProcessInfo = .processInfo) {
        self.init(environment: processInfo.environment, osVersion: processInfo.operatingSystemVersion)
    }

    /// 環境変数を直接与える初期化（テストと GUI からの注入に使う）。
    public init(
        environment env: [String: String],
        osVersion version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) {
        let home = env["HOME"] ?? NSHomeDirectory()
        self.home = PathGuard.normalize(home)
        self.configDir = PathGuard.normalize(env["DISCLEAN_CONFIG_DIR"] ?? home + "/.config/disclean")
        self.stateDir = PathGuard.normalize(env["DISCLEAN_STATE_DIR"] ?? home + "/.local/state/disclean")
        self.osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        self.osBuild = DiscleanEnvironment.readOSBuild()
        #if arch(arm64)
            self.arch = "arm64"
        #else
            self.arch = "x86_64"
        #endif
        if let lang = env["DISCLEAN_LANG"] {
            self.isJapanese = lang.hasPrefix("ja")
        } else {
            self.isJapanese = (Locale.preferredLanguages.first ?? "en").hasPrefix("ja")
        }
        self.noColor = env["NO_COLOR"] != nil
    }

    /// `sysctl kern.osversion` のビルド番号（例 "25F84"）。
    static func readOSBuild() -> String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }
}

/// 実行環境の記録（OS ドリフト判定用、`$DISCLEAN_STATE_DIR/env.json`）。
public struct EnvSample: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let osVersion: String
    public let osBuild: String
    public let arch: String
    public let discleanVersion: String
    public let recordedAt: Date

    public init(env: DiscleanEnvironment, recordedAt: Date = Date()) {
        self.schemaVersion = 1
        self.osVersion = env.osVersion
        self.osBuild = env.osBuild
        self.arch = env.arch
        self.discleanVersion = DiscleanVersion.current
        self.recordedAt = recordedAt
    }
}

/// `major.minor.patch` の緩い比較（欠けた要素は 0 とみなす）。
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in trimmed.split(separator: ".") {
            guard let value = Int(part.prefix(while: { $0.isNumber })), value >= 0 else { return nil }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
