import Foundation
import Testing
@testable import DiscleanKit

/// 一時ディレクトリ上に閉じた実行環境。実ユーザーの隔離庫・設定には触れない。
struct Sandbox {
    let home: String
    let env: DiscleanEnvironment
    let config: Config

    init(excluded: [String] = [], ttlDays: Int = 7) throws {
        let base = NSTemporaryDirectory() + "disclean-it-" + UUID().uuidString
        let fm = FileManager.default
        try fm.createDirectory(atPath: base + "/Library/Caches", withIntermediateDirectories: true)
        home = base
        env = DiscleanEnvironment(environment: [
            "HOME": base,
            "DISCLEAN_STATE_DIR": base + "/state",
            "DISCLEAN_CONFIG_DIR": base + "/config",
            "DISCLEAN_LANG": "en",
        ])
        config = Config(quarantineTtlDays: ttlDays, concurrency: 2, excludedPaths: excluded, autoUpdate: false)
        try fm.createDirectory(atPath: env.rulesOverrideDir, withIntermediateDirectories: true)
    }

    /// fixture 用のユーザールールを置く。
    func installFixtureRule(
        id: String = "test-fixture", relativePath: String = "Library/Caches/fixture",
        tier: Tier = .a, minAgeDays: Int? = nil
    ) throws {
        var rule: [String: Any] = [
            "id": id, "title": "fixture", "tier": tier.rawValue, "kind": "directory",
            "paths": ["~/" + relativePath], "whatIsLost": "test data",
        ]
        if let minAgeDays { rule["minAgeDays"] = minAgeDays }
        let data = try JSONSerialization.data(withJSONObject: [rule], options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: env.rulesOverrideDir + "/00-test-fixture.json"))
    }

    /// 1MiB のファイルを n 個作る。
    @discardableResult
    func makeFixtureFiles(count: Int = 3, relativePath: String = "Library/Caches/fixture") throws -> [String] {
        let dir = home + "/" + relativePath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for i in 0..<count {
            let path = dir + "/file-\(i).bin"
            try Data(repeating: 0x41, count: 1024 * 1024).write(to: URL(fileURLWithPath: path))
            paths.append(path)
        }
        return paths
    }

    func catalog() -> RuleCatalog {
        RuleCatalogLoader(env: env, config: config).load()
    }

    var audit: AuditLog { AuditLog(dir: env.auditDir) }

    func executor() -> Executor {
        Executor(env: env, config: config, audit: audit, catalogVersion: 0)
    }
}

@Suite("Scanner / Quarantine / Restore / Purge / Audit の一巡")
struct LifecycleTests {
    @Test("Scanner は読み取りだけで、隔離庫に何も書かない")
    func scanIsReadOnly() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        try sandbox.makeFixtureFiles()
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let item = try #require(result.items.first { $0.ruleId == "test-fixture" })
        #expect(item.state == .ready)
        #expect(item.bytes >= 3 * 1024 * 1024 && item.bytes <= 3_670_016)
        #expect(item.fileCount == 3)
        let quarantineEntries = (try? FileManager.default.contentsOfDirectory(atPath: sandbox.env.quarantineDir)) ?? []
        #expect(quarantineEntries.isEmpty)
    }

    @Test("キャッシュが効くと 2 回目は cacheHit になる")
    func scanCache() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        try sandbox.makeFixtureFiles()
        let scanner = Scanner(env: sandbox.env, config: sandbox.config)
        _ = await scanner.scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let second = await scanner.scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        #expect(second.items.first?.cacheHit == true)
    }

    @Test("apply → undo で全件が元の場所に戻り、バイト数が一致する")
    func applyThenUndo() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        let files = try sandbox.makeFixtureFiles()
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)

        #expect(outcome.quarantined.count == 3)
        #expect(outcome.failed.isEmpty)
        for file in files { #expect(!FileManager.default.fileExists(atPath: file)) }

        let undone = try sandbox.executor().undo(runId: outcome.runId)
        #expect(undone.restored.count == 3)
        #expect(undone.restored.reduce(Int64(0)) { $0 + $1.bytes } == outcome.reclaimedBytes)
        for file in files { #expect(FileManager.default.fileExists(atPath: file)) }
    }

    @Test("dry-run では 1 件も移動しない")
    func dryRun() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        let files = try sandbox.makeFixtureFiles()
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: true)
        #expect(outcome.quarantined.count == 3)
        for file in files { #expect(FileManager.default.fileExists(atPath: file)) }
    }

    @Test("復元先に同名があるときは戻さず隔離庫に残す")
    func destinationExists() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        let files = try sandbox.makeFixtureFiles(count: 1)
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.quarantined.count == 1)
        try Data("blocker".utf8).write(to: URL(fileURLWithPath: files[0]))

        let undone = try sandbox.executor().undo(runId: outcome.runId)
        #expect(undone.restored.isEmpty)
        #expect(undone.skipped.first?.reason == "destination-exists")
        let index = QuarantineStore(root: sandbox.env.quarantineDir).loadIndex()
        #expect(index.runs.first?.entries.count == 1)
    }

    @Test("TTL 0 なら次回起動時に実削除される")
    func purgeExpired() async throws {
        let sandbox = try Sandbox(ttlDays: 0)
        try sandbox.installFixtureRule()
        try sandbox.makeFixtureFiles(count: 2)
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(!outcome.quarantined.isEmpty)

        let store = QuarantineStore(root: sandbox.env.quarantineDir)
        let purged = try store.purgeExpired(now: Date().addingTimeInterval(1))
        #expect(purged.count == 1)
        #expect(store.loadIndex().runs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sandbox.env.quarantineDir + "/" + outcome.runId))
    }

    @Test("監査ログに書けないときは 1 件も消さない")
    func auditFailureBlocksDeletion() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        let files = try sandbox.makeFixtureFiles()
        try FileManager.default.createDirectory(atPath: sandbox.env.auditDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: sandbox.env.auditDir)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: sandbox.env.auditDir)
        }

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a])
        #expect(throws: AuditError.self) {
            _ = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        }
        for file in files { #expect(FileManager.default.fileExists(atPath: file)) }
    }

    @Test("監査ログは操作を 1 行ずつ追記する")
    func auditRecords() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        try sandbox.makeFixtureFiles(count: 2)
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a])
        _ = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        let (records, corrupt) = sandbox.audit.read(since: nil, until: nil, action: .apply)
        #expect(records.count == 2)
        #expect(corrupt.isEmpty)
        #expect(records.allSatisfy { !$0.osBuild.isEmpty && $0.result == .ok })
    }

    @Test("除外パス配下は隔離しない")
    func excludedPathsAreSkipped() async throws {
        let sandbox = try Sandbox(excluded: ["~/Library/Caches/fixture"])
        try sandbox.installFixtureRule()
        let files = try sandbox.makeFixtureFiles()
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        // 除外パスはカタログ検証の時点で弾かれる（ルール自体が無効になる）。
        #expect(result.items.first(where: { $0.ruleId == "test-fixture" }) == nil)
        for file in files { #expect(FileManager.default.fileExists(atPath: file)) }
    }

    @Test("Tier C は plan で選べない")
    func tierCCannotBeSelected() async throws {
        let sandbox = try Sandbox()
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), tiers: [.c])
        #expect(throws: PlannerError.self) {
            _ = try Planner().plan(from: result, tiers: [.c])
        }
    }

    @Test("Planner は Tier A を既定選択し、Tier B は含めない")
    func plannerDefaults() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule(id: "fixture-a", relativePath: "Library/Caches/a", tier: .a)
        try sandbox.makeFixtureFiles(count: 1, relativePath: "Library/Caches/a")
        var ruleB: [String: Any] = [
            "id": "fixture-b", "title": "b", "tier": "B", "kind": "directory",
            "paths": ["~/Library/Caches/b"], "whatIsLost": "x",
        ]
        ruleB["enabled"] = true
        let data = try JSONSerialization.data(withJSONObject: [ruleB])
        try data.write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/01-b.json"))
        try sandbox.makeFixtureFiles(count: 1, relativePath: "Library/Caches/b")

        let result = await Scanner(env: sandbox.env, config: sandbox.config).scan(catalog: sandbox.catalog())
        let plan = try Planner().plan(from: result)
        #expect(plan.selected.contains { $0.ruleId == "fixture-a" })
        #expect(!plan.selected.contains { $0.ruleId == "fixture-b" })
    }
}
