import Foundation

/// 走っている仕事を、外から止めるための旗。
///
/// 走査も移動も「1 件ずつ」進むため、旗が立った時点で**その件の切れ目**で止まる。
/// 途中のファイルを半端な状態にしないのは、移動が `rename(2)` 1 回で終わるから
/// （やりかけの移動という状態が存在しない）。
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// `Scanner` / `Executor` に渡す判定。何度呼んでも安全。
    public var check: @Sendable () -> Bool {
        { [self] in isCancelled }
    }
}
