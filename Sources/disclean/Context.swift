import Foundation
import DiscleanKit

/// 全サブコマンドが共有する起動処理（設定読込・カタログ読込・失効処理・更新チェック）。
struct Context {
    let env: DiscleanEnvironment
    let config: Config
    let catalog: RuleCatalog
    let audit: AuditLog
    let out: Output
    var updateState: UpdateState
    let expiredPurges: [PurgedRun]
    private let updateTask: Task<UpdateCheckOutcome?, Never>?

    init(noUpdate: Bool, quiet: Bool = false) {
        let env = DiscleanEnvironment()
        let config = Config.load(env: env)
        let state = UpdateState.load(env: env)
        let audit = AuditLog(dir: env.auditDir)

        self.env = env
        self.config = config
        self.audit = audit
        self.out = Output(env: env)
        self.updateState = state
        self.catalog = RuleCatalogLoader(env: env, config: config).load(revocations: Set(state.revocations))

        // 失効した隔離は起動時に 1 回だけ片付ける。
        let store = QuarantineStore(root: env.quarantineDir)
        self.expiredPurges = (try? store.purgeExpired()) ?? []

        // 更新チェックはコマンド本体と並行に走らせ、完了を待たない。
        let updater = Updater(env: env, config: config, audit: audit)
        if !noUpdate && config.autoUpdate && updater.isDue(state: state) {
            self.updateTask = Task.detached(priority: .background) {
                var localState = state
                let outcome = await updater.check(state: &localState)
                localState.save(env: env)
                Context.completionBox.set(outcome)
                return outcome
            }
        } else {
            self.updateTask = nil
        }
        _ = quiet
    }

    /// 進行中の更新チェックが既に終わっていれば結果を返す。
    /// ネットワークの完了は待たない（最大 0.4 秒だけ様子を見て、間に合わなければ次回に回す）。
    func finishedUpdateOutcome() async -> UpdateCheckOutcome? {
        guard updateTask != nil else { return nil }
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if let outcome = Context.completionBox.value { return outcome }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return Context.completionBox.value
    }

    /// 隔離庫の失効通知と、前回チェックで保留になっている更新の案内。
    func printPendingNotices() {
        if !expiredPurges.isEmpty {
            let bytes = expiredPurges.reduce(Int64(0)) { $0 + $1.bytes }
            out.print(
                out.styled(
                    out.japanese
                        ? "隔離庫の期限切れ \(expiredPurges.count) 件を削除しました（\(Output.bytes(bytes))）"
                        : "purged \(expiredPurges.count) expired quarantine run(s) (\(Output.bytes(bytes)))",
                    .dim))
        }
        if updateState.lastCheckResult == .pendingApproval, let staged = updateState.stagedCatalogVersion {
            out.print(
                out.styled(
                    out.japanese
                        ? "掃除ルールの更新があります（カタログ \(staged)）。内容は disclean update で確認できます。"
                        : "A rule catalog update is available (catalog \(staged)). Run `disclean update` to review it.",
                    .yellow))
        }
        if updateState.lastCheckResult == .rejected, let reason = updateState.lastFailureReason {
            out.warn(
                out.japanese
                    ? "更新は適用していません（理由: \(reason)）"
                    : "update was not applied (reason: \(reason))")
        }
    }

    var catalogVersion: Int { updateState.appliedCatalogVersion }

    /// バックグラウンドのチェック結果を受け取る箱（プロセス内で 1 個）。
    static let completionBox = OutcomeBox()
}

/// 完了した更新チェックの結果を保持する。
final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: UpdateCheckOutcome?

    var value: UpdateCheckOutcome? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ outcome: UpdateCheckOutcome) {
        lock.lock()
        storage = outcome
        lock.unlock()
    }
}
