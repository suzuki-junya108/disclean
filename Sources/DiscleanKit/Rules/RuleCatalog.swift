import Foundation

/// カタログ読込時のエラー 1 件。
public struct CatalogError: Sendable, Equatable, Codable {
    public let file: String
    public let ruleId: String?
    public let reason: String

    public init(file: String, ruleId: String?, reason: String) {
        self.file = file
        self.ruleId = ruleId
        self.reason = reason
    }
}

/// 有効カタログ（読込・検証済み）。
public struct RuleCatalog: Sendable {
    public let entries: [CatalogEntry]
    public let errors: [CatalogError]
    /// OS 条件などで無効化されたルール（一覧には出すが対象にしない）。
    public let disabledByOS: [DisabledRule]

    public var rules: [Rule] { entries.map(\.rule) }

    public func rule(id: String) -> Rule? { entries.first { $0.rule.id == id }?.rule }
    public func source(of id: String) -> RuleSource? { entries.first { $0.rule.id == id }?.source }
    public func rules(tier: Tier) -> [Rule] { rules.filter { $0.tier == tier } }

    init(entries: [CatalogEntry], errors: [CatalogError], disabledByOS: [DisabledRule]) {
        self.entries = entries
        self.errors = errors
        self.disabledByOS = disabledByOS
    }
}

/// 同梱 → 自動更新 → ユーザー の順に読み、後から読んだものが同一 id を置換する。
public struct RuleCatalogLoader: Sendable {
    private let env: DiscleanEnvironment
    private let guardian: PathGuard
    private let osVersion: SemanticVersion?

    public init(env: DiscleanEnvironment, config: Config) {
        self.env = env
        self.guardian = PathGuard(
            home: env.home, stateDir: env.stateDir, configDir: env.configDir, excludedPaths: config.excludedPaths)
        self.osVersion = SemanticVersion(env.osVersion)
    }

    /// - Parameter revocations: 更新 manifest により無効化されたルール ID。
    public func load(revocations: Set<String> = []) -> RuleCatalog {
        var byId: [String: CatalogEntry] = [:]
        var errors: [CatalogError] = []
        var order: [String] = []

        func absorb(_ loaded: [(Rule, String)], source: RuleSource) {
            for (rule, file) in loaded {
                if let violation = validate(rule) {
                    errors.append(CatalogError(file: file, ruleId: rule.id, reason: violation))
                    continue
                }
                if byId[rule.id] == nil { order.append(rule.id) }
                byId[rule.id] = CatalogEntry(rule: rule, source: source)
            }
        }

        let builtin = loadBuiltin(&errors)
        absorb(builtin, source: .builtin)
        absorb(loadDirectory(env.updatesDir + "/active/rules", errors: &errors), source: .update)
        absorb(loadDirectory(env.rulesOverrideDir, errors: &errors), source: .user)

        var entries: [CatalogEntry] = []
        var disabledByOS: [DisabledRule] = []
        for id in order {
            guard let entry = byId[id] else { continue }
            if revocations.contains(id) && entry.source != .user {
                disabledByOS.append(DisabledRule(ruleId: id, reason: "revoked"))
                continue
            }
            guard entry.rule.enabled else { continue }
            if let reason = osIneligibility(entry.rule) {
                disabledByOS.append(DisabledRule(ruleId: id, reason: reason))
                continue
            }
            entries.append(entry)
        }
        return RuleCatalog(entries: entries, errors: errors, disabledByOS: disabledByOS)
    }

    /// OS 条件（minMacOS / maxMacOS）で対象外かどうか。
    func osIneligibility(_ rule: Rule) -> String? {
        guard let osVersion else { return nil }
        if let minRaw = rule.minMacOS {
            guard let minVersion = SemanticVersion(minRaw) else { return "invalid-minMacOS" }
            if osVersion < minVersion { return "os-unsupported" }
        }
        if let maxRaw = rule.maxMacOS {
            guard let maxVersion = SemanticVersion(maxRaw) else { return "invalid-maxMacOS" }
            if maxVersion < osVersion { return "os-unsupported" }
        }
        return nil
    }

    /// スキーマ・禁止パス・型ごとの必須フィールドを検証する。違反なら理由を返す。
    func validate(_ rule: Rule) -> String? {
        if rule.id.isEmpty { return "empty id" }
        if rule.id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) == nil {
            return "id must be kebab-case: \"\(rule.id)\""
        }
        if rule.timeoutSeconds < 1 || rule.timeoutSeconds > Rule.maxTimeoutSeconds {
            return "timeoutSeconds must be 1...\(Rule.maxTimeoutSeconds)"
        }
        if rule.tier == .c && rule.kind != .report { return "tier C rules must be report kind" }
        if rule.tier == .c && (rule.manualSteps ?? "").isEmpty { return "tier C rules require manualSteps" }
        switch rule.kind {
        case .directory:
            // 場所はツールに聞く場合もある。その場合は解決したパスを実行直前に検証する。
            if rule.pathsFrom == nil, (rule.paths ?? []).isEmpty {
                return "directory rules require paths or pathsFrom"
            }
            // `pathsFrom` と併記された既定の場所も、代替として使われるため必ず検証する。
            // ひな形（`*` を含む）は、ワイルドカードより前の固定部分を検査する。
            // 広げた先は解決時にもう一度、同じ規則で検証する。
            for path in rule.paths ?? [] {
                let checked = PathPattern.hasWildcard(path) ? PathPattern.staticPrefix(path) : path
                if let violation = guardian.validateRulePath(checked) {
                    return "forbidden path \"\(path)\" (\(violation.rawValue))"
                }
            }
        case .command:
            guard rule.command != nil else { return "command rules require command" }
        case .report:
            if (rule.paths ?? []).isEmpty && rule.sizeProbe == nil {
                return "report rules require paths or sizeProbe"
            }
        // report 型は削除しないため、パスの制約は $HOME 外も許す（表示のみ）。
        }
        return nil
    }

    private func loadBuiltin(_ errors: inout [CatalogError]) -> [(Rule, String)] {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: nil) else {
            errors.append(CatalogError(file: "<builtin>", ruleId: nil, reason: "bundled rules not found"))
            return []
        }
        return loadDirectory(url.path, errors: &errors)
    }

    private func loadDirectory(_ dir: String, errors: inout [CatalogError]) -> [(Rule, String)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var result: [(Rule, String)] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let file = dir + "/" + name
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: file))
                let rules = try JSONIO.decoder().decode([Rule].self, from: data)
                var seen = Set<String>()
                for rule in rules {
                    if !seen.insert(rule.id).inserted {
                        errors.append(CatalogError(file: file, ruleId: rule.id, reason: "duplicate id"))
                        continue
                    }
                    result.append((rule, file))
                }
            } catch {
                errors.append(CatalogError(file: file, ruleId: nil, reason: "\(error)"))
            }
        }
        return result
    }
}
