import Foundation
import Testing

@testable import DiscleanKit

@Suite("ひな形で書いた場所（1 台の機械に縛られないルール）")
struct GlobRuleTests {
    /// シミュレータのように「機械ごとに変わる ID」が挟まる形を作る。
    private func makeSimulatorLike(_ sandbox: Sandbox, devices: [String], megabytes: Int) throws {
        for device in devices {
            let caches =
                sandbox.home + "/Library/Developer/CoreSimulator/Devices/\(device)"
                + "/data/Containers/Data/Application/APP-1/Library/Caches"
            try FileManager.default.createDirectory(atPath: caches, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: megabytes * 1024 * 1024)
                .write(to: URL(fileURLWithPath: caches + "/model.bin"))
        }
    }

    private func writeGlobRule(_ sandbox: Sandbox, id: String = "glob-cache") throws {
        let rule: [String: Any] = [
            "id": id, "title": "glob", "tier": "A", "kind": "directory",
            "paths": [
                "~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Caches"
            ],
            "whatIsLost": "rebuilt on next launch",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-glob.json"))
    }

    @Test("機械ごとに変わる ID をまたいで、全部の場所を見つける")
    func matchesEveryDevice() async throws {
        let sandbox = try Sandbox()
        try makeSimulatorLike(sandbox, devices: ["DEV-A", "DEV-B", "DEV-C"], megabytes: 2)
        try writeGlobRule(sandbox)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["glob-cache"])
        let item = try #require(result.items.first { $0.ruleId == "glob-cache" })
        #expect(item.state == .ready)
        #expect(item.paths.count == 3, "3 台ぶんの場所が当たる")
        #expect(item.bytes >= 6 * 1024 * 1024)
        #expect(!item.pathsTruncated)
    }

    @Test("当たった場所を隔離庫へ移し、元に戻せる")
    func quarantinesAndRestores() async throws {
        let sandbox = try Sandbox()
        try makeSimulatorLike(sandbox, devices: ["DEV-A", "DEV-B"], megabytes: 3)
        try writeGlobRule(sandbox)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["glob-cache"])
        let item = try #require(result.items.first { $0.ruleId == "glob-cache" })

        let plan = try Planner().plan(from: result, tiers: [.a])
        let outcome = try sandbox.executor().apply(plan: plan, catalog: sandbox.catalog(), dryRun: false)
        #expect(outcome.reclaimedBytes == item.bytes, "見せた量と動かす量が一致する")
        #expect(outcome.quarantined.count == 2)

        let undone = try sandbox.executor().undo(runId: outcome.runId)
        #expect(undone.restored.reduce(Int64(0)) { $0 + $1.bytes } == item.bytes)
        var st = stat()
        let restored =
            sandbox.home
            + "/Library/Developer/CoreSimulator/Devices/DEV-A/data/Containers/Data/Application/APP-1/Library/Caches"
        #expect(lstat(restored, &st) == 0, "元の場所に戻っている")
    }

    /// ひな形の途中にリンクを置いても、その先へは進まない。
    @Test("リンクの先には広がらない")
    func doesNotEscapeThroughSymlinks() async throws {
        let sandbox = try Sandbox()
        try makeSimulatorLike(sandbox, devices: ["DEV-A"], megabytes: 1)
        let outside = NSTemporaryDirectory() + "disclean-outside-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: outside + "/data/Containers/Data/Application/APP-1/Library/Caches",
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: outside) }
        try FileManager.default.createSymbolicLink(
            atPath: sandbox.home + "/Library/Developer/CoreSimulator/Devices/ESCAPE",
            withDestinationPath: outside)
        try writeGlobRule(sandbox)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["glob-cache"])
        let item = try #require(result.items.first { $0.ruleId == "glob-cache" })
        #expect(item.paths.count == 1, "リンク経由の場所は当たらない")
        #expect(item.paths.allSatisfy { $0.contains("DEV-A") })
    }

    @Test("除外した場所には当たらない")
    func respectsExclusions() async throws {
        let sandbox = try Sandbox(excluded: ["~/Library/Developer/CoreSimulator/Devices/DEV-B"])
        try makeSimulatorLike(sandbox, devices: ["DEV-A", "DEV-B"], megabytes: 2)
        try writeGlobRule(sandbox)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["glob-cache"])
        let item = try #require(result.items.first { $0.ruleId == "glob-cache" })
        #expect(item.paths.count == 1)
        #expect(item.paths.allSatisfy { !$0.contains("DEV-B") })
    }
}
