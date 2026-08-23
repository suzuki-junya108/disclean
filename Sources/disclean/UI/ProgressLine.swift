import DiscleanKit
import Foundation

/// 端末で待たされている間、1 行だけを書き換えて「いま何をしているか」を出す。
/// 画面（GUI）が板で見せるのと同じことを、端末では 1 行で言う。
///
/// - 出力先は stderr。stdout は結果と `--json` のために空けておく。
/// - 端末でないときは何も書かない（ログやパイプを汚さない）。
final class ProgressLine: @unchecked Sendable {
    private let japanese: Bool
    private let enabled: Bool
    private let home: String
    private let lock = NSLock()
    private var lastDraw: TimeInterval = 0
    private var drew = false

    /// - Parameter quiet: `--json` のように、進捗を出してはいけないとき true。
    init(out: Output, home: String = "", quiet: Bool = false) {
        self.japanese = out.japanese
        self.home = home
        self.enabled = !quiet && isatty(STDERR_FILENO) == 1
    }

    /// `Executor` などに渡す受け取り口。
    var handler: WorkProgressHandler {
        { [weak self] progress in self?.report(progress) }
    }

    func report(_ progress: WorkProgress) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        // 速く流れすぎると読めないので、20 分の 1 秒に 1 回だけ描き直す。
        let now = Date().timeIntervalSince1970
        let finished = progress.total > 0 && progress.completed >= progress.total
        guard now - lastDraw >= 0.05 || !drew || finished else { return }
        lastDraw = now
        drew = true
        write("\r\u{001B}[2K" + line(for: progress))
    }

    /// 行を消して次の出力に譲る。作業が終わったら必ず呼ぶ。
    func finish() {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if drew { write("\r\u{001B}[2K") }
        drew = false
    }

    private func line(for progress: WorkProgress) -> String {
        var parts = [label(progress.step)]
        if let fraction = progress.fraction {
            parts.append(bar(fraction))
            parts.append("\(progress.completed)/\(progress.total)")
        }
        let head = parts.joined(separator: "  ")
        guard !progress.path.isEmpty else { return head }
        // 端末の幅に収める。切るのは真ん中（末尾のファイル名こそ読みたいところなので残す）。
        let room = max(12, terminalWidth() - head.count - 3)
        return head + "  " + middleTruncated(shortened(progress.path), limit: room)
    }

    /// ホームの下は `~` に畳む。GUI と同じ見え方にそろえる。
    private func shortened(_ path: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func middleTruncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let tail = max(8, limit * 2 / 3)
        let head = max(0, limit - tail - 1)
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    /// 8 目盛りの棒。細かい割合より「どのくらい残っているか」が読めればよい。
    private func bar(_ fraction: Double) -> String {
        let filled = Int((fraction * 8).rounded(.down))
        return "[" + String(repeating: "█", count: filled)
            + String(repeating: "·", count: 8 - filled) + "]"
    }

    private func label(_ step: WorkProgress.Step) -> String {
        switch step {
        case .counting: japanese ? "数えています" : "counting"
        case .measuring: japanese ? "測っています" : "measuring"
        case .moving: japanese ? "隔離庫へ移しています" : "moving to quarantine"
        case .deleting: japanese ? "完全に削除しています" : "deleting for good"
        case .restoring: japanese ? "元に戻しています" : "restoring"
        case .running: japanese ? "外部ツールを動かしています" : "running tool"
        }
    }

    private func terminalWidth() -> Int {
        var size = winsize()
        guard ioctl(STDERR_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 20 else { return 80 }
        return Int(size.ws_col)
    }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
