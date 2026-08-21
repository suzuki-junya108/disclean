import Foundation

/// 本体のバージョン。リリースタグ (`v<version>`) と一致させる。
public enum DiscleanVersion {
    public static let current = "0.2.1"
}

/// 全 CLI サブコマンド共通の終了コード規約（要件 §4.1）。
public enum DiscleanExitCode: Int32, Sendable {
    case success = 0
    case generalError = 1
    case argumentError = 2
    case permissionDenied = 3
    case partialFailure = 4
    case invalidCatalog = 5
    case quarantineInconsistent = 6
    case updateVerificationFailed = 7
    case interrupted = 130
}
