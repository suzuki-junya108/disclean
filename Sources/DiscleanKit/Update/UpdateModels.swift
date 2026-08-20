import Foundation

/// manifest が指すファイル 1 件。
public struct ManifestFile: Codable, Sendable, Equatable {
    public let name: String
    public let sha256: String
    public let bytes: Int64
}

/// 本体の最新版情報（manifest に同梱し、追加の通信を発生させない）。
public struct AppRelease: Codable, Sendable, Equatable {
    public let version: String
    public let minMacOS: String
    public let assets: [AppAsset]
}

public struct AppAsset: Codable, Sendable, Equatable {
    public let name: String
    public let url: String
    public let sha256: String
    public let bytes: Int64
}

/// 配信されるカタログ 1 版分のメタデータ（署名対象）。
public struct CatalogManifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let catalogVersion: Int
    public let publishedAt: Date
    public let expiresAt: Date
    public let minDiscleanVersion: String
    public let keyId: String
    public let archive: ManifestFile
    public let files: [ManifestFile]
    public let revocations: [String]
    public let latestApp: AppRelease?
}

/// 直近の更新チェックの結果。
public enum CheckResult: String, Codable, Sendable {
    case never
    case ok
    case noUpdate
    case pendingApproval
    case networkError
    case rejected
}

public enum InstallMethod: String, Codable, Sendable {
    case brew
    case app
    case manual
}

/// 更新の進行状態（`$DISCLEAN_STATE_DIR/updates/state.json`）。
public struct UpdateState: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var appliedCatalogVersion: Int = 0
    public var appliedAt: Date?
    public var appliedPublishedAt: Date?
    public var stagedCatalogVersion: Int?
    public var lastCheckedAt: Date?
    public var lastCheckResult: CheckResult = .never
    public var lastFailureReason: String?
    public var availableAppVersion: String?
    public var installMethod: InstallMethod = .manual
    public var revocations: [String] = []

    public init() {}

    public static func load(env: DiscleanEnvironment) -> UpdateState {
        (try? JSONIO.read(UpdateState.self, at: env.updatesDir + "/state.json")) ?? UpdateState()
    }

    public func save(env: DiscleanEnvironment) {
        try? JSONIO.writeAtomically(self, to: env.updatesDir + "/state.json")
    }
}

/// 差分 1 件の種類。
public enum ChangeKind: String, Codable, Sendable {
    case ruleAdded
    case ruleRemoved
    case pathAdded
    case pathRemoved
    case tierRaised
    case tierLowered
    case commandChanged
    case ageRelaxed
    case ageTightened
    case osScopeWidened
    case osScopeNarrowed
    case revoked
    case textChanged

    /// 削除対象が増える方向か（= 承認必須）。
    public var isExpanding: Bool {
        switch self {
        case .ruleAdded, .pathAdded, .tierRaised, .commandChanged, .ageRelaxed, .osScopeWidened: true
        case .ruleRemoved, .pathRemoved, .tierLowered, .ageTightened, .osScopeNarrowed, .revoked, .textChanged: false
        }
    }

    /// 中立（表示だけが変わる）か。
    public var isNeutral: Bool { self == .textChanged }
}

public struct DiffEntry: Codable, Sendable, Equatable {
    public let ruleId: String
    public let change: ChangeKind
    public let before: String?
    public let after: String?
    public let newPaths: [String]
}

/// 現行カタログと staged カタログの差分。
public struct CatalogDiff: Codable, Sendable, Equatable {
    public var expanding: [DiffEntry] = []
    public var shrinking: [DiffEntry] = []
    public var neutral: [DiffEntry] = []

    public var isEmpty: Bool { expanding.isEmpty && shrinking.isEmpty && neutral.isEmpty }
    public var requiresApproval: Bool { !expanding.isEmpty }
    public var newPaths: [String] { expanding.flatMap(\.newPaths) }
}
