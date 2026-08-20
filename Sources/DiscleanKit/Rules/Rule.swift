import Foundation

/// ルールのリスク階層。
public enum Tier: String, Codable, Sendable, CaseIterable {
    /// 既定で選択される。再取得が容易でリスクが低い。
    case a = "A"
    /// 既定では選択されない。実行前に内容の確認を要する。
    case b = "B"
    /// 削除しない。サイズと手動手順の提示のみ行う。
    case c = "C"
}

/// ルールの処理方式。
public enum RuleKind: String, Codable, Sendable {
    /// 対象ディレクトリの中身を隔離庫へ移動する（undo 可）。
    case directory
    /// 外部 CLI を実行する（隔離庫を経由しないため undo 不可）。
    case command
    /// 計測と表示のみ（Tier C はすべてこの型）。
    case report
}

/// 外部コマンド 1 件の仕様。シェルを経由せず `Process` に直接渡す。
public struct CommandSpec: Codable, Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let expectSuccess: Bool

    public init(executable: String, arguments: [String] = [], expectSuccess: Bool = true) {
        self.executable = executable
        self.arguments = arguments
        self.expectSuccess = expectSuccess
    }

    private enum CodingKeys: String, CodingKey {
        case executable, arguments, expectSuccess
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        executable = try c.decode(String.self, forKey: .executable)
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        expectSuccess = try c.decodeIfPresent(Bool.self, forKey: .expectSuccess) ?? true
    }
}

/// クリーンアップ対象 1 件の定義。同梱 JSON・更新カタログ・ユーザー JSON すべてこの形。
public struct Rule: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let titleJa: String
    public let tier: Tier
    public let kind: RuleKind
    public let paths: [String]?
    public let command: CommandSpec?
    public let sizeProbe: CommandSpec?
    public let detect: CommandSpec?
    public let minAgeDays: Int?
    public let requiresQuitApps: [String]?
    public let whatIsLost: String
    public let whatIsLostJa: String
    public let manualSteps: String?
    public let enabled: Bool
    public let timeoutSeconds: Int
    /// この OS 以上でのみ有効（例 "14.0"）。未指定は下限なし。
    public let minMacOS: String?
    /// この OS 以下でのみ有効（例 "26.99"）。未指定は上限なし。
    public let maxMacOS: String?
    /// 最後に実機確認した OS ビルド（例 "25F84"）。
    public let verifiedOn: String?

    public static let defaultTimeoutSeconds = 180
    public static let maxTimeoutSeconds = 900

    private enum CodingKeys: String, CodingKey {
        case id, title, titleJa, tier, kind, paths, command, sizeProbe, detect
        case minAgeDays, requiresQuitApps, whatIsLost, whatIsLostJa, manualSteps
        case enabled, timeoutSeconds, minMacOS, maxMacOS, verifiedOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        titleJa = try c.decodeIfPresent(String.self, forKey: .titleJa) ?? (try c.decode(String.self, forKey: .title))
        tier = try c.decode(Tier.self, forKey: .tier)
        kind = try c.decode(RuleKind.self, forKey: .kind)
        paths = try c.decodeIfPresent([String].self, forKey: .paths)
        command = try c.decodeIfPresent(CommandSpec.self, forKey: .command)
        sizeProbe = try c.decodeIfPresent(CommandSpec.self, forKey: .sizeProbe)
        detect = try c.decodeIfPresent(CommandSpec.self, forKey: .detect)
        minAgeDays = try c.decodeIfPresent(Int.self, forKey: .minAgeDays)
        requiresQuitApps = try c.decodeIfPresent([String].self, forKey: .requiresQuitApps)
        whatIsLost = try c.decode(String.self, forKey: .whatIsLost)
        whatIsLostJa =
            try c.decodeIfPresent(String.self, forKey: .whatIsLostJa)
            ?? (try c.decode(String.self, forKey: .whatIsLost))
        manualSteps = try c.decodeIfPresent(String.self, forKey: .manualSteps)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? Rule.defaultTimeoutSeconds
        minMacOS = try c.decodeIfPresent(String.self, forKey: .minMacOS)
        maxMacOS = try c.decodeIfPresent(String.self, forKey: .maxMacOS)
        verifiedOn = try c.decodeIfPresent(String.self, forKey: .verifiedOn)
    }

    // swiftlint:disable:next function_default_parameter_at_end
    public init(
        id: String,
        title: String,
        titleJa: String? = nil,
        tier: Tier,
        kind: RuleKind,
        paths: [String]? = nil,
        command: CommandSpec? = nil,
        sizeProbe: CommandSpec? = nil,
        detect: CommandSpec? = nil,
        minAgeDays: Int? = nil,
        requiresQuitApps: [String]? = nil,
        whatIsLost: String,
        whatIsLostJa: String? = nil,
        manualSteps: String? = nil,
        enabled: Bool = true,
        timeoutSeconds: Int = Rule.defaultTimeoutSeconds,
        minMacOS: String? = nil,
        maxMacOS: String? = nil,
        verifiedOn: String? = nil
    ) {
        self.id = id
        self.title = title
        self.titleJa = titleJa ?? title
        self.tier = tier
        self.kind = kind
        self.paths = paths
        self.command = command
        self.sizeProbe = sizeProbe
        self.detect = detect
        self.minAgeDays = minAgeDays
        self.requiresQuitApps = requiresQuitApps
        self.whatIsLost = whatIsLost
        self.whatIsLostJa = whatIsLostJa ?? whatIsLost
        self.manualSteps = manualSteps
        self.enabled = enabled
        self.timeoutSeconds = timeoutSeconds
        self.minMacOS = minMacOS
        self.maxMacOS = maxMacOS
        self.verifiedOn = verifiedOn
    }

    /// 表示用のタイトル（ロケールに応じて日本語と英語を選ぶ）。
    public func displayTitle(japanese: Bool) -> String { japanese ? titleJa : title }

    /// 「何を失うか」の表示文字列。
    public func displayWhatIsLost(japanese: Bool) -> String { japanese ? whatIsLostJa : whatIsLost }
}

/// ルールの出所。ユーザー定義が最優先、次に自動更新カタログ、最後に同梱。
public enum RuleSource: String, Codable, Sendable, Comparable {
    case builtin
    case update
    case user

    private var precedence: Int {
        switch self {
        case .builtin: 0
        case .update: 1
        case .user: 2
        }
    }

    public static func < (lhs: RuleSource, rhs: RuleSource) -> Bool {
        lhs.precedence < rhs.precedence
    }
}

/// カタログに載った 1 件（ルール + 出所）。
public struct CatalogEntry: Sendable, Equatable {
    public let rule: Rule
    public let source: RuleSource

    public init(rule: Rule, source: RuleSource) {
        self.rule = rule
        self.source = source
    }
}
