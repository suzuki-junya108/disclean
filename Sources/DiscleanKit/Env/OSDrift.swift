import Foundation

/// OS の変化検知の結果。
public struct OSDriftReport: Sendable {
    public let osVersion: String
    public let osBuild: String
    /// 前回実行時のビルド番号。変化していなければ nil。
    public let changedSince: String?
    public let rulesDisabledByOS: [DisabledRule]
    /// OS 変化後に対象パスが見つからなくなったルール。
    public let rulesMissingAfterOSChange: [MissingRulePath]
}

/// OS のバージョン・ビルドを記録し、変化したらキャッシュを捨てて再評価する。
public struct OSDrift: Sendable {
    private let env: DiscleanEnvironment

    public init(env: DiscleanEnvironment) {
        self.env = env
    }

    public func previousSample() -> EnvSample? {
        try? JSONIO.read(EnvSample.self, at: env.envFile)
    }

    public func record(now: Date = Date()) {
        try? JSONIO.writeAtomically(EnvSample(env: env, recordedAt: now), to: env.envFile)
    }

    /// - Parameter catalog: OS 条件で無効化されたルールを含む読込済みカタログ。
    public func evaluate(catalog: RuleCatalog, updateRecord: Bool = true) -> OSDriftReport {
        let previous = previousSample()
        let changed = (previous != nil && previous?.osBuild != env.osBuild) ? previous?.osBuild : nil

        var missing: [MissingRulePath] = []
        if changed != nil {
            // OS が変わった直後はキャッシュを信用しない（パスの意味が変わりうる）。
            var cache = ScanCache.load(path: env.cacheDir + "/scan-cache.json")
            cache.clear()
            cache.save(path: env.cacheDir + "/scan-cache.json")

            for entry in catalog.entries where entry.rule.kind != .command {
                for rawPath in entry.rule.paths ?? [] {
                    let path = PathGuard.normalize(Expand.tilde(rawPath, home: env.home))
                    var st = stat()
                    if lstat(path, &st) != 0 && errno == ENOENT {
                        missing.append(MissingRulePath(ruleId: entry.rule.id, path: path))
                    }
                }
            }
        }
        if updateRecord { record() }
        return OSDriftReport(
            osVersion: env.osVersion, osBuild: env.osBuild, changedSince: changed,
            rulesDisabledByOS: catalog.disabledByOS, rulesMissingAfterOSChange: missing)
    }
}

/// OS 条件などで無効になったルール 1 件。
public struct DisabledRule: Sendable, Equatable {
    public let ruleId: String
    public let reason: String

    public init(ruleId: String, reason: String) {
        self.ruleId = ruleId
        self.reason = reason
    }
}

/// OS 変化後に見つからなくなった対象パス 1 件。
public struct MissingRulePath: Sendable, Equatable {
    public let ruleId: String
    public let path: String
}
