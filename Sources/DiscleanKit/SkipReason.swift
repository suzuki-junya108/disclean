import Foundation

/// スキップ・失敗の理由を、人が読める言葉にする。
/// 機械可読な理由コード（JSON の `reason`）はそのままに、表示だけを翻訳する。
public enum SkipReason {
    public static func describe(_ reason: String, japanese: Bool) -> String {
        if reason.hasPrefix(appRunningPrefix) {
            let bundleId = String(reason.dropFirst(appRunningPrefix.count))
            return japanese ? "アプリが起動中（\(bundleId)）" : "app is running (\(bundleId))"
        }
        return (japanese ? japaneseTable : englishTable)[reason] ?? reason
    }

    private static let appRunningPrefix = "app-running:"

    private static let japaneseTable: [String: String] = [
        "too-recent": "新しすぎます",
        "empty": "空でした",
        "not-found": "見つかりません",
        "permission-denied": "権限がありません",
        "tool-not-found": "ツールが入っていません",
        "daemon-not-running": "ツールが動いていません",
        "symlink": "リンクなので辿りません",
        "cross-volume": "別のディスクにあります",
        "outside-home": "ホームの外です",
        "too-shallow": "対象として浅すぎます",
        "forbidden-root": "触らない場所です",
        "excluded": "除外に入っています",
        "self-referential": "ディスクリン自身の保存先です",
        "destination-exists": "戻す先に同じ名前があります",
        "report-only": "見るだけの区分です",
        "os-unsupported": "この macOS では対象外です",
        "revoked": "配信元が停止しました",
        "unknown-rule": "ルールが見つかりません",
    ]

    private static let englishTable: [String: String] = [
        "too-recent": "too recent",
        "empty": "already empty",
        "not-found": "not found",
        "permission-denied": "permission denied",
        "tool-not-found": "tool not installed",
        "daemon-not-running": "tool is not running",
        "symlink": "symlink (not followed)",
        "cross-volume": "on a different volume",
        "outside-home": "outside home",
        "too-shallow": "path too shallow",
        "forbidden-root": "protected location",
        "excluded": "excluded",
        "self-referential": "disclean's own directory",
        "destination-exists": "destination already exists",
        "report-only": "report only",
        "os-unsupported": "not applicable on this macOS",
        "revoked": "revoked by the publisher",
        "unknown-rule": "unknown rule",
    ]
}
