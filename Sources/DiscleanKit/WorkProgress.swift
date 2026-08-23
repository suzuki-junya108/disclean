import Foundation

/// 時間のかかる処理が「いま何をしているか」を 1 件ずつ知らせる報せ。
///
/// 画面（GUI）も端末（CLI）も、この 1 種類だけを見れば進捗を描ける。
/// 「グルグル回るだけで何が起きているか分からない」状態を作らないために、
/// 走っている処理は必ずこれを流す。
public struct WorkProgress: Sendable, Equatable {
    /// いま何をしているか。表示する言葉は受け取る側が決める。
    public enum Step: String, Sendable {
        /// 数えている（総数がまだ分からない）
        case counting
        /// 大きさを測っている（読み取りだけ）
        case measuring
        /// 隔離庫へ移している
        case moving
        /// 完全に削除している（戻せない）
        case deleting
        /// 元の場所へ戻している
        case restoring
        /// 外部ツールを動かしている
        case running
    }

    public let step: Step
    /// どのルールの作業か。人に見せる名前は受け取る側が引く。
    public let ruleId: String
    /// いま触っている場所。空文字なら「対象なし（準備中）」。
    public let path: String
    /// 終わった件数。
    public let completed: Int
    /// 全体の件数。0 は「まだ数えていない／数えられない」であって「0 件」ではない。
    public let total: Int
    /// この 1 件の大きさ。分からなければ 0。
    public let bytes: Int64

    public init(
        step: Step, ruleId: String = "", path: String = "", completed: Int = 0, total: Int = 0,
        bytes: Int64 = 0
    ) {
        self.step = step
        self.ruleId = ruleId
        self.path = path
        self.completed = completed
        self.total = total
        self.bytes = bytes
    }

    /// 0.0〜1.0。総数が分からないときは nil（不定表示にする）。
    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

/// 進捗の受け取り口。既定は「誰も見ていない」。
public typealias WorkProgressHandler = @Sendable (WorkProgress) -> Void

/// 何もしない受け取り口（既定値）。
public let ignoreProgress: WorkProgressHandler = { _ in }
