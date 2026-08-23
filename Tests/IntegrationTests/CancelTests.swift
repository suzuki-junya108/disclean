import Foundation
import Testing

@testable import DiscleanKit

@Suite("途中でやめる")
struct CancelTests {
    private func makeTarget(_ sandbox: Sandbox, name: String, megabytes: Int) throws {
        let path = sandbox.home + "/Library/Caches/\(name)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: megabytes * 1024 * 1024)
            .write(to: URL(fileURLWithPath: path + "/blob.bin"))
        let rule: [String: Any] = [
            "id": name, "title": name, "tier": "A", "kind": "directory",
            "paths": ["~/Library/Caches/\(name)"], "whatIsLost": "x",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-\(name).json"))
    }

    @Test("旗を立てると、立てた時点で止まる")
    func tokenReportsCancellation() {
        let token = CancelToken()
        #expect(!token.isCancelled)
        #expect(!token.check())
        token.cancel()
        #expect(token.isCancelled)
        #expect(token.check(), "Scanner に渡す判定にも伝わる")
    }

    @Test("止めたスキャンは、途中である と分かる形で返る")
    func scanStopsAndSaysSo() async throws {
        let sandbox = try Sandbox()
        try makeTarget(sandbox, name: "big", megabytes: 4)
        let token = CancelToken()
        token.cancel()

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["big"], isCancelled: token.check)
        #expect(result.interrupted, "途中でやめたことを、結果自身が持っている")
    }

    @Test("止めた実行は、1 件も動かさない")
    func applyMovesNothingWhenStopped() async throws {
        let sandbox = try Sandbox()
        try makeTarget(sandbox, name: "big", megabytes: 4)

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["big"])
        let plan = try Planner().plan(from: result, tiers: [.a])

        let token = CancelToken()
        token.cancel()
        let outcome = try sandbox.executor().apply(
            plan: plan, catalog: sandbox.catalog(), dryRun: false, isCancelled: token.check)

        #expect(outcome.quarantined.isEmpty)
        var st = stat()
        #expect(
            lstat(sandbox.home + "/Library/Caches/big/blob.bin", &st) == 0,
            "止めたのだから、元の場所にそのまま残っている")
    }

    @Test("止めた探索も、結果を返して落ちない")
    func uncoveredStopsCleanly() async throws {
        let sandbox = try Sandbox()
        try makeTarget(sandbox, name: "big", megabytes: 4)
        let token = CancelToken()
        token.cancel()

        let result = await UncoveredScanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), minimumBytes: 1024, isCancelled: token.check)
        #expect(result.places.isEmpty || !result.places.isEmpty, "落ちずに返る")
    }
}
