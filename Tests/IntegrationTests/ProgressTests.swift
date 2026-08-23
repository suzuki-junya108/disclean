import Foundation
import Testing

@testable import DiscleanKit

/// 進みぐあいの報せを集める箱。同期実行の中から呼ばれるが、
/// 受け取り口が `@Sendable` なので鍵をかけて渡す。
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WorkProgress] = []

    var handler: WorkProgressHandler {
        { progress in
            self.lock.lock()
            self.storage.append(progress)
            self.lock.unlock()
        }
    }

    var events: [WorkProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("待たされている間、いま何をしているかが 1 件ずつ分かる")
struct ProgressTests {
    @Test("隔離庫へ移すとき、対象 1 件ごとに報せが出る")
    func applyReportsEveryItem() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        let files = try sandbox.makeFixtureFiles(count: 5)
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a], select: [], deselect: [])

        let collector = Collector()
        let outcome = try sandbox.executor().apply(
            plan: plan, catalog: sandbox.catalog(), dryRun: false, onProgress: collector.handler)

        #expect(outcome.quarantined.count == files.count)
        let events = collector.events
        #expect(events.first?.step == .counting, "まず数えていることを知らせる")

        let moving = events.filter { $0.step == .moving }
        #expect(moving.count == files.count, "移す 1 件ごとに報せが出る")
        for file in files {
            #expect(moving.contains { $0.path == file }, "\(file) の報せがある")
        }
        #expect(moving.allSatisfy { $0.total == files.count }, "総数が最初から分かっている")
        #expect(moving.map(\.completed) == Array(0..<files.count), "1 件ずつ進む")
    }

    @Test("完全に削除するとき、ファイル 1 件ごとに報せが出て、最後は全部終わっている")
    func purgeReportsEveryFile() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        try sandbox.makeFixtureFiles(count: 4)
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a], select: [], deselect: [])
        let applied = try sandbox.executor().apply(
            plan: plan, catalog: sandbox.catalog(), dryRun: false)

        let collector = Collector()
        let store = QuarantineStore(root: sandbox.env.quarantineDir)
        let purged = try store.purge(runId: applied.runId, all: false, onProgress: collector.handler)

        #expect(purged.count == 1)
        let deleting = collector.events.filter { $0.step == .deleting && !$0.path.isEmpty }
        #expect(deleting.count == 4, "隔離庫にある 4 ファイルを 1 件ずつ消す")
        #expect(deleting.allSatisfy { $0.total == 4 })
        #expect(deleting.map(\.completed) == [0, 1, 2, 3])
        // 見せるのは隔離庫の中の置き場所ではなく、元あった場所。
        #expect(
            deleting.allSatisfy { $0.path.hasPrefix(sandbox.home + "/Library/Caches/fixture/") },
            "元の場所で知らせる")
        #expect(deleting.allSatisfy { $0.ruleId == "test-fixture" })

        // 実際に消えている（報せを出すために消し残さない）。
        #expect(!FileManager.default.fileExists(atPath: sandbox.env.quarantineDir + "/" + applied.runId))
        #expect(store.loadIndex().runs.isEmpty)
    }

    @Test("元に戻すときも、1 件ごとに報せが出る")
    func undoReportsEveryItem() async throws {
        let sandbox = try Sandbox()
        try sandbox.installFixtureRule()
        try sandbox.makeFixtureFiles(count: 3)
        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["test-fixture"])
        let plan = try Planner().plan(from: result, tiers: [.a], select: [], deselect: [])
        let applied = try sandbox.executor().apply(
            plan: plan, catalog: sandbox.catalog(), dryRun: false)

        let collector = Collector()
        let outcome = try sandbox.executor().undo(runId: applied.runId, onProgress: collector.handler)

        #expect(outcome.restored.count == 3)
        let restoring = collector.events.filter { $0.step == .restoring }
        #expect(restoring.count == 3)
        #expect(restoring.map(\.completed) == [0, 1, 2])
        #expect(restoring.allSatisfy { $0.total == 3 })
    }

    @Test("しらべている間も、何本目まで測ったかが分かる")
    func scanReportsEveryRule() async throws {
        let sandbox = try Sandbox()
        try sandbox.installDirectoryRule("fixture-a", path: "~/Library/Caches/a")
        try sandbox.installDirectoryRule("fixture-b", path: "~/Library/Caches/b")
        try sandbox.makeFixtureFiles(count: 1, relativePath: "Library/Caches/a")
        try sandbox.makeFixtureFiles(count: 1, relativePath: "Library/Caches/b")

        let collector = Collector()
        _ = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(
                catalog: sandbox.catalog(), ruleIds: ["fixture-a", "fixture-b"],
                onProgress: collector.handler)

        let measured = collector.events.filter { $0.step == .measuring }
        #expect(measured.count == 2)
        #expect(measured.map(\.completed) == [1, 2], "測り終わった数が増えていく")
        #expect(measured.allSatisfy { $0.total == 2 })
    }

    @Test("総数が分かるまでは、割合を作らない")
    func fractionIsNilUntilTotalIsKnown() {
        #expect(WorkProgress(step: .counting).fraction == nil)
        #expect(WorkProgress(step: .moving, completed: 1, total: 4).fraction == 0.25)
    }
}
