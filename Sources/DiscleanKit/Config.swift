import Foundation

/// ユーザー設定（`$DISCLEAN_CONFIG_DIR/config.json`）。すべて既定値を持つ。
public struct Config: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var quarantineTtlDays: Int
    public var concurrency: Int
    public var excludedPaths: [String]
    public var autoUpdate: Bool
    public var updateIntervalHours: Int
    public var updateEndpoint: String

    public static let defaultEndpoint = "https://github.com/suzuki-junya108/disclean/releases/latest/download/"

    public init(
        schemaVersion: Int = 1,
        quarantineTtlDays: Int = 7,
        concurrency: Int = min(8, ProcessInfo.processInfo.activeProcessorCount),
        excludedPaths: [String] = ["~/Sync"],
        autoUpdate: Bool = true,
        updateIntervalHours: Int = 24,
        updateEndpoint: String = Config.defaultEndpoint
    ) {
        self.schemaVersion = schemaVersion
        self.quarantineTtlDays = quarantineTtlDays
        self.concurrency = concurrency
        self.excludedPaths = excludedPaths
        self.autoUpdate = autoUpdate
        self.updateIntervalHours = updateIntervalHours
        self.updateEndpoint = updateEndpoint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        quarantineTtlDays = try c.decodeIfPresent(Int.self, forKey: .quarantineTtlDays) ?? fallback.quarantineTtlDays
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? fallback.concurrency
        excludedPaths = try c.decodeIfPresent([String].self, forKey: .excludedPaths) ?? fallback.excludedPaths
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? fallback.autoUpdate
        updateIntervalHours =
            try c.decodeIfPresent(Int.self, forKey: .updateIntervalHours) ?? fallback.updateIntervalHours
        updateEndpoint = try c.decodeIfPresent(String.self, forKey: .updateEndpoint) ?? fallback.updateEndpoint
    }

    /// 環境変数は設定ファイルより優先する。範囲外の値は既定値に丸める。
    public func applyingEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Config {
        var config = self
        if let raw = env["DISCLEAN_QUARANTINE_TTL_DAYS"], let value = Int(raw), (1...90).contains(value) {
            config.quarantineTtlDays = value
        }
        if let raw = env["DISCLEAN_CONCURRENCY"], let value = Int(raw), (1...32).contains(value) {
            config.concurrency = value
        }
        if let raw = env["DISCLEAN_AUTO_UPDATE"] {
            config.autoUpdate = !(raw == "0" || raw.lowercased() == "false")
        }
        if let raw = env["DISCLEAN_UPDATE_INTERVAL_HOURS"], let value = Int(raw), (1...168).contains(value) {
            config.updateIntervalHours = value
        }
        if let raw = env["DISCLEAN_UPDATE_ENDPOINT"], !raw.isEmpty {
            config.updateEndpoint = raw.hasSuffix("/") ? raw : raw + "/"
        }
        return config
    }

    /// 設定ファイルを読む。無い・壊れている場合は既定値を返す（起動を妨げない）。
    public static func load(env: DiscleanEnvironment) -> Config {
        let stored = (try? JSONIO.read(Config.self, at: env.configFile)) ?? Config()
        return stored.applyingEnvironment()
    }

    public func save(env: DiscleanEnvironment) throws {
        try JSONIO.writeAtomically(self, to: env.configFile)
    }

    /// 範囲検証。UI 側の入力チェックと CLI で共用する。
    public func validationErrors() -> [String] {
        var errors: [String] = []
        if !(1...90).contains(quarantineTtlDays) { errors.append("quarantineTtlDays must be 1...90") }
        if !(1...32).contains(concurrency) { errors.append("concurrency must be 1...32") }
        if !(1...168).contains(updateIntervalHours) { errors.append("updateIntervalHours must be 1...168") }
        if URL(string: updateEndpoint)?.scheme != "https" && !updateEndpoint.hasPrefix("http://127.0.0.1") {
            errors.append("updateEndpoint must be https")
        }
        return errors
    }
}
