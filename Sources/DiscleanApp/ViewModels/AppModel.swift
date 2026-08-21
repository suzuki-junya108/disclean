import AppKit
import DiscleanKit
import Foundation
import Observation

/// 画面の状態。CLI と同じ `DiscleanKit` を通して同じ隔離庫・監査ログを読み書きする。
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case scanning
        case results
        case applying
        case done
    }

    enum Section: String, CaseIterable, Identifiable {
        case clean
        case quarantine
        case history
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clean: "片づける"
            case .quarantine: "隔離庫"
            case .history: "履歴"
            case .settings: "設定"
            }
        }
    }

    private(set) var env = DiscleanEnvironment()
    private(set) var catalog: RuleCatalog?
    private(set) var scanResult: ScanResult?
    private(set) var applyOutcome: ApplyOutcome?
    private(set) var updateOutcome: UpdateCheckOutcome?
    private(set) var quarantineRuns: [QuarantineRun] = []
    private(set) var auditRecords: [AuditRecord] = []
    private(set) var doctorReport: DoctorReport?

    var config: Config
    var updateState: UpdateState
    var section: Section = .clean
    var phase: Phase = .scanning
    var selection: Set<String> = []
    var errorMessage: String?
    var showConfirmSheet = false
    var showUpdateSheet = false
    var scanProgressLabel = ""
    var purgedLastRun = false
    /// 直前の実行を隔離庫から戻した。完全削除の案内はもう出さない。
    var lastRunUndone = false

    private var audit: AuditLog

    init() {
        let env = DiscleanEnvironment()
        self.env = env
        self.config = Config.load(env: env)
        self.updateState = UpdateState.load(env: env)
        self.audit = AuditLog(dir: env.auditDir)
    }

    var selectedItems: [ScanItem] {
        (scanResult?.readyItems ?? []).filter { selection.contains($0.ruleId) }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    var needsPermissionGuide: Bool {
        guard let doctorReport else { return false }
        return !doctorReport.fullDiskAccess
    }

    /// 起動時とスキャンボタンで呼ぶ。読み取りだけを行う。
    func scan() async {
        phase = .scanning
        errorMessage = nil
        let env = self.env
        let config = self.config
        let state = self.updateState
        scanProgressLabel = "ルールを読み込んでいます"

        let loaded = await Task.detached {
            RuleCatalogLoader(env: env, config: config).load(revocations: Set(state.revocations))
        }.value
        catalog = loaded

        scanProgressLabel = "大きさを測っています"
        let result = await Scanner(env: env, config: config).scan(catalog: loaded, tiers: [.a, .b, .c])
        scanResult = result
        // 既定は Tier A のみ選択（Tier B は明示選択、Tier C は選択不可）。
        selection = Set(result.readyItems.filter { $0.tier == .a }.map(\.ruleId))
        phase = .results

        let doctor = Doctor(env: env, config: config)
        doctorReport = doctor.run(catalog: loaded, updateState: state)
        refreshQuarantine()
        refreshHistory()
    }

    /// 選んだものを隔離庫へ移す。
    func apply() async {
        guard let catalog, let scanResult else { return }
        phase = .applying
        purgedLastRun = false
        lastRunUndone = false
        do {
            let plan = try Planner().plan(
                from: scanResult, tiers: [], select: Array(selection), deselect: [])
            let executor = Executor(
                env: env, config: config, audit: audit,
                catalogVersion: updateState.appliedCatalogVersion)
            let outcome = try executor.apply(plan: plan, catalog: catalog, dryRun: false)
            applyOutcome = outcome
            phase = .done
            refreshQuarantine()
            refreshHistory()
        } catch let error as AuditError {
            errorMessage = "記録できないため、何も削除していません（\(error)）"
            phase = .results
        } catch {
            errorMessage = "\(error)"
            phase = .results
        }
    }

    func undo(runId: String) {
        do {
            let executor = Executor(
                env: env, config: config, audit: audit,
                catalogVersion: updateState.appliedCatalogVersion)
            let outcome = try executor.undo(runId: runId)
            if outcome.restored.isEmpty, let first = outcome.skipped.first {
                errorMessage = "戻せませんでした: \(first.reason)（\(first.path)）"
            } else if runId == applyOutcome?.runId {
                lastRunUndone = true
            }
            refreshQuarantine()
            refreshHistory()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// 直前の実行分を、いま完全に削除して空き容量にする。
    func purgeLastRun() {
        guard let runId = applyOutcome?.runId else { return }
        purge(runId: runId)
        purgedLastRun = true
    }

    func purge(runId: String) {
        do {
            _ = try QuarantineStore(root: env.quarantineDir).purge(runId: runId, all: false)
            if runId == applyOutcome?.runId { purgedLastRun = true }
            refreshQuarantine()
            refreshHistory()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func refreshQuarantine() {
        quarantineRuns = QuarantineStore(root: env.quarantineDir).loadIndex().runs
            .sorted { $0.createdAt > $1.createdAt }
    }

    func refreshHistory() {
        auditRecords = Array(audit.read(since: nil, until: nil, action: nil).records.prefix(500))
    }

    /// 更新を確認する。取得は自動でも、消す対象が増える変更は承認を求める。
    func checkForUpdates() async {
        let updater = Updater(env: env, config: config, audit: audit)
        var state = updateState
        let outcome = await updater.check(state: &state, timeout: 60)
        state.save(env: env)
        updateState = state
        updateOutcome = outcome
        if outcome.requiresApproval { showUpdateSheet = true }
        if let failure = outcome.failure {
            errorMessage = "受け取った更新は適用していません（理由: \(failure.rawValue)）"
        }
    }

    func applyStagedUpdate() async {
        guard let staged = updateState.stagedCatalogVersion else { return }
        do {
            let updater = Updater(env: env, config: config, audit: audit)
            var state = updateState
            let store = CatalogStore(env: env)
            try updater.apply(version: staged, manifest: store.stagedManifest(version: staged), state: &state)
            state.save(env: env)
            updateState = state
            showUpdateSheet = false
            await scan()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func saveConfig() {
        do {
            try config.save(env: env)
        } catch {
            errorMessage = "設定を保存できませんでした: \(error)"
        }
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let url { NSWorkspace.shared.open(url) }
    }

    func openQuarantineInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: env.quarantineDir)])
    }

    func openRulesFolder() {
        try? FileManager.default.createDirectory(
            atPath: env.rulesOverrideDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: env.rulesOverrideDir)])
    }
}
