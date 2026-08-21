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

    /// directory 型のユーザールールを 1 件置く。
    func installDirectoryRule(_ id: String, path: String, minAgeDays: Int? = nil) throws {
        var rule: [String: Any] = [
            "id": id, "title": id, "tier": "A", "kind": "directory",
            "paths": [path], "whatIsLost": "test data",
        ]
        if let minAgeDays { rule["minAgeDays"] = minAgeDays }
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: env.rulesOverrideDir + "/00-\(id).json"))
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

    @Test("外部ツールが空けた量を、実行の前後を測って報告する")
    func commandRuleReportsReclaimedBytes() async throws {
        let sandbox = try Sandbox()
        let cache = sandbox.home + "/fakecache"
        try FileManager.default.createDirectory(atPath: cache, withIntermediateDirectories: true)
        for i in 0..<3 {
            try Data(repeating: 0x41, count: 2 * 1024 * 1024)
                .write(to: URL(fileURLWithPath: cache + "/f\(i).bin"))
        }
        let rule: [String: Any] = [
            "id": "measured-cache", "title": "measured", "tier": "A", "kind": "command",
            "command": ["executable": "/bin/rm", "arguments": ["-rf", cache]],
            "measure": ["kind": "paths", "paths": [cache]],
            "whatIsLost": "cache",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-measured.json"))

        // 実行前に量が分かること
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["measured-cache"])
        let item = try #require(result.items.first { $0.ruleId == "measured-cache" })
        #expect(item.state == .ready)
        #expect(item.sizeKnown)
        #expect(item.bytes >= 6 * 1024 * 1024)

        // 実行後に「実際に空けた量」が出ること
        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        let command = try #require(outcome.commandsRun.first)
        #expect(command.reclaimedBytes ?? 0 >= 6 * 1024 * 1024)
        #expect(outcome.reclaimedBytes >= 6 * 1024 * 1024)
        #expect(!outcome.hasUnmeasuredCommand)
        #expect(!FileManager.default.fileExists(atPath: cache))
    }

    @Test("測る方法がないルールは「不明」として扱い、0 バイトと混同しない")
    func unmeasuredCommandRuleIsUnknown() async throws {
        let sandbox = try Sandbox()
        let rule: [String: Any] = [
            "id": "unmeasured", "title": "unmeasured", "tier": "A", "kind": "command",
            "command": ["executable": "/bin/echo", "arguments": ["done"]],
            "whatIsLost": "nothing",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-unmeasured.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["unmeasured"])
        let item = try #require(result.items.first { $0.ruleId == "unmeasured" })
        #expect(item.state == .ready)
        #expect(!item.sizeKnown)

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.commandsRun.first?.reclaimedBytes == nil)
        #expect(outcome.hasUnmeasuredCommand)
    }

    @Test("対象が空の外部ツールは、実行せずスキップする")
    func emptyCommandRuleIsSkipped() async throws {
        let sandbox = try Sandbox()
        let rule: [String: Any] = [
            "id": "empty-cache", "title": "empty", "tier": "A", "kind": "command",
            "command": ["executable": "/bin/echo", "arguments": ["nothing"]],
            "measure": ["kind": "paths", "paths": [sandbox.home + "/does-not-exist"]],
            "whatIsLost": "nothing",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-empty.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["empty-cache"])
        let item = try #require(result.items.first { $0.ruleId == "empty-cache" })
        #expect(item.state == .skipped)
        #expect(item.reason == "empty")
    }

    @Test("入れ子のディレクトリでも、表示した量と実際に移す量が一致する")
    func nestedDirectoryReportsFullSize() async throws {
        let sandbox = try Sandbox()
        let target = sandbox.home + "/Library/Caches/nested"
        for name in ["a", "b", "c"] {
            let dir = target + "/\(name)/sub"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 4 * 1024 * 1024)
                .write(to: URL(fileURLWithPath: dir + "/data.bin"))
        }
        try sandbox.installDirectoryRule("nested", path: target)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["nested"])
        let shown = result.totalBytes
        #expect(shown >= 12 * 1024 * 1024)

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        // ディレクトリの中身を数え落とすと、ここが桁違いに小さくなる。
        #expect(outcome.reclaimedBytes == shown)
    }

    @Test("最終更新で絞るルールは、絞った後の量だけを見せる")
    func minAgeDaysIsReflectedInTheEstimate() async throws {
        let sandbox = try Sandbox()
        let target = sandbox.home + "/Library/Caches/aged"
        for name in ["old", "new"] {
            let dir = target + "/\(name)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 3 * 1024 * 1024)
                .write(to: URL(fileURLWithPath: dir + "/data.bin"))
        }
        let old = Date().addingTimeInterval(-30 * 86_400)
        for path in [target + "/old/data.bin", target + "/old"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
        }
        try sandbox.installDirectoryRule("aged", path: target, minAgeDays: 3)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["aged"])
        let shown = result.totalBytes
        #expect(shown >= 3 * 1024 * 1024)
        #expect(shown < 6 * 1024 * 1024)  // 新しい方を数えていないこと

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.reclaimedBytes == shown)
        #expect(outcome.skipped.contains { $0.reason == "too-recent" })
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

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["fixture-a", "fixture-b"])
        let plan = try Planner().plan(from: result)
        #expect(plan.selected.contains { $0.ruleId == "fixture-a" })
        #expect(!plan.selected.contains { $0.ruleId == "fixture-b" })
    }
}

@Suite("最近使ったばかりのものを、空と取り違えない")
struct RecencyReasonTests {
    @Test("中身が新しいだけのときは「新しすぎます」と報告する")
    func recentContentsAreNotReportedAsEmpty() async throws {
        let sandbox = try Sandbox()
        let target = sandbox.home + "/Library/Caches/busy"
        try FileManager.default.createDirectory(
            atPath: target + "/app", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: target + "/app/now.bin"))
        try sandbox.installDirectoryRule("busy", path: target, minAgeDays: 3)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["busy"])
        let item = try #require(result.items.first { $0.ruleId == "busy" })
        #expect(item.state == .skipped)
        #expect(item.reason == "too-recent")
    }

    @Test("本当に空のときだけ「空でした」と報告する")
    func trulyEmptyIsReportedAsEmpty() async throws {
        let sandbox = try Sandbox()
        let target = sandbox.home + "/Library/Caches/vacant"
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        try sandbox.installDirectoryRule("vacant", path: target, minAgeDays: 3)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["vacant"])
        let item = try #require(result.items.first { $0.ruleId == "vacant" })
        #expect(item.reason == "empty")
    }

    @Test("入れ物に触っただけでは「最近使った」と見なさない")
    func touchingTheFolderDoesNotCountAsUse() async throws {
        let sandbox = try Sandbox()
        let target = sandbox.home + "/Library/Caches/stale"
        let inner = target + "/app"
        try FileManager.default.createDirectory(atPath: inner, withIntermediateDirectories: true)
        let file = inner + "/old.bin"
        try Data(repeating: 0x41, count: 2 * 1024 * 1024).write(to: URL(fileURLWithPath: file))
        let old = Date().addingTimeInterval(-40 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file)
        // 入れ物だけ「いま」触られた状態にする
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: inner)
        try sandbox.installDirectoryRule("stale", path: target, minAgeDays: 3)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["stale"])
        let item = try #require(result.items.first { $0.ruleId == "stale" })
        #expect(item.state == .ready)
        #expect(item.bytes >= 2 * 1024 * 1024)

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.reclaimedBytes == item.bytes)
    }
}

@Suite("ツールに場所を聞くルール")
struct ToolResolvedPathTests {
    /// 場所をツールに聞いても、見せた量と動かす量は一致する。
    @Test("解決したパスを、そのまま隔離庫へ移す")
    func resolvedPathIsQuarantined() async throws {
        let sandbox = try Sandbox()
        let cache = sandbox.home + "/Library/Caches/toolcache"
        try FileManager.default.createDirectory(
            atPath: cache + "/sub", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 5 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: cache + "/sub/data.bin"))
        let rule: [String: Any] = [
            "id": "tool-cache", "title": "tool", "tier": "A", "kind": "directory",
            "pathsFrom": ["command": ["executable": "/bin/echo", "arguments": [cache]]],
            "whatIsLost": "cache",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-tool.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["tool-cache"])
        let item = try #require(result.items.first { $0.ruleId == "tool-cache" })
        #expect(item.state == .ready)
        #expect(item.undoable, "ツールに任せず自分で移すので、戻せるはず")
        #expect(item.bytes >= 5 * 1024 * 1024)

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.reclaimedBytes == item.bytes)

        // 戻せること
        let undone = try sandbox.executor().undo(runId: outcome.runId)
        #expect(undone.restored.reduce(Int64(0)) { $0 + $1.bytes } == item.bytes)
    }

    @Test("ツールが触ってはいけない場所を答えたら、対象にしない")
    func rejectsForbiddenResolvedPath() async throws {
        let sandbox = try Sandbox()
        let rule: [String: Any] = [
            "id": "evil-tool", "title": "evil", "tier": "A", "kind": "directory",
            "pathsFrom": ["command": ["executable": "/bin/echo", "arguments": ["/System/Library"]]],
            "whatIsLost": "everything",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-evil.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["evil-tool"])
        let item = try #require(result.items.first { $0.ruleId == "evil-tool" })
        #expect(item.state == .skipped)
        #expect(item.reason == "forbidden-root")
    }

    @Test("ツールが入っていなければ、見つからない扱いにする")
    func missingToolIsSkipped() async throws {
        let sandbox = try Sandbox()
        let rule: [String: Any] = [
            "id": "absent-tool", "title": "absent", "tier": "A", "kind": "directory",
            "pathsFrom": ["command": ["executable": "/nonexistent/tool", "arguments": ["cache"]]],
            "whatIsLost": "cache",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-absent.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["absent-tool"])
        let item = try #require(result.items.first { $0.ruleId == "absent-tool" })
        #expect(item.reason == "tool-not-found")
    }

    @Test("古い 0 バイトの記録は、実体を測り直して直す")
    func healsLegacyZeroByteEntries() async throws {
        let sandbox = try Sandbox()
        let store = QuarantineStore(root: sandbox.env.quarantineDir)
        let runId = "01TESTTESTTESTTESTTESTTEST"
        let runDirectory = try store.createRunDirectory(runId: runId)
        try FileManager.default.createDirectory(
            atPath: runDirectory + "/rule", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 3 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: runDirectory + "/rule/blob.bin"))

        var index = QuarantineIndex()
        index.runs = [
            QuarantineRun(
                runId: runId, createdAt: Date(), expiresAt: Date().addingTimeInterval(86_400),
                entries: [
                    QuarantineEntry(
                        ruleId: "rule", originalPath: sandbox.home + "/Library/Caches/x/blob.bin",
                        quarantineRelativePath: "rule/blob.bin", bytes: 0, isDirectory: false,
                        movedAt: Date())
                ])
        ]
        try store.saveIndex(index)

        let reloaded = store.loadIndex()
        #expect(reloaded.runs.first?.totalBytes ?? 0 >= 3 * 1024 * 1024)
    }
}
