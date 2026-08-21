import Foundation
import Testing
@testable import DiscleanKit

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

    /// npm 10 は `npm config get cache` を「保護された項目」として拒む。
    /// ツールが答えられないだけで片づけを諦めない。
    @Test("ツールが答えられないときは、ルールに書かれた既定の場所を使う")
    func fallsBackToDeclaredPathWhenToolCannotAnswer() async throws {
        let sandbox = try Sandbox()
        let cache = sandbox.home + "/Library/Caches/fallbackcache"
        try FileManager.default.createDirectory(atPath: cache, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: cache + "/data.bin"))
        let rule: [String: Any] = [
            "id": "mute-tool", "title": "mute", "tier": "A", "kind": "directory",
            "paths": ["~/Library/Caches/fallbackcache"],
            "pathsFrom": ["command": ["executable": "/usr/bin/false", "arguments": []]],
            "whatIsLost": "cache",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-mute.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["mute-tool"])
        let item = try #require(result.items.first { $0.ruleId == "mute-tool" })
        #expect(item.state == .ready)
        #expect(item.bytes >= 4 * 1024 * 1024)

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.reclaimedBytes == item.bytes)
    }

    /// 既定の場所が無ければ、黙って別の場所を消したりせず、対象外にする。
    @Test("答えられず、既定の場所も無ければ、対象にしない")
    func withoutFallbackTheRuleIsSkipped() async throws {
        let sandbox = try Sandbox()
        let rule: [String: Any] = [
            "id": "mute-empty", "title": "mute", "tier": "A", "kind": "directory",
            "paths": ["~/Library/Caches/neverexists"],
            "pathsFrom": ["command": ["executable": "/usr/bin/false", "arguments": []]],
            "whatIsLost": "cache",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-mute-empty.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["mute-empty"])
        let item = try #require(result.items.first { $0.ruleId == "mute-empty" })
        #expect(item.state == .skipped)
        #expect(item.reason == "tool-not-found")
    }

    /// ツールが範囲外を答えたときも、既定の場所に実体があればそちらを使う。
    /// 使うのは検証を通った場所だけで、ツールの答えは決して使わない。
    @Test("範囲外を答えられたときも、既定の場所があればそちらを使う")
    func usesDeclaredPathWhenToolAnswersOutsideHome() async throws {
        let sandbox = try Sandbox()
        let cache = sandbox.home + "/Library/Caches/outsidecache"
        try FileManager.default.createDirectory(atPath: cache, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: cache + "/data.bin"))
        let rule: [String: Any] = [
            "id": "outside-tool", "title": "outside", "tier": "A", "kind": "directory",
            "paths": ["~/Library/Caches/outsidecache"],
            "pathsFrom": ["command": ["executable": "/bin/echo", "arguments": ["/System/Library"]]],
            "whatIsLost": "cache",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-outside.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["outside-tool"])
        let item = try #require(result.items.first { $0.ruleId == "outside-tool" })
        #expect(item.state == .ready)
        #expect(item.paths == [PathGuard.normalize(cache)], "ツールの答えは使わない")
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
