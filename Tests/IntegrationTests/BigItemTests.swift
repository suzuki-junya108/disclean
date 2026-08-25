import Foundation
import Testing

@testable import DiscleanKit

/// 進みぐあいを集める箱（同期実行の中から呼ばれるので鍵をかける）。
private final class ProgressBox: @unchecked Sendable {
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

@Suite("大きいもの: 選んだものだけが、ルールと同じ道で隔離庫へ入る")
struct BigItemTests {
    @discardableResult
    private func makeFile(_ sandbox: Sandbox, _ relative: String, megabytes: Int) throws -> String {
        let full = sandbox.home + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: megabytes * 1024 * 1024)
            .write(to: URL(fileURLWithPath: full))
        return full
    }

    @Test("選んだものだけが隔離庫へ移り、undo で元の場所に戻る")
    func movesOnlyWhatWasChosen() async throws {
        let sandbox = try Sandbox()
        let chosen = try makeFile(sandbox, "Movies/holiday.mov", megabytes: 3)
        let untouched = try makeFile(sandbox, "Movies/keep.mov", megabytes: 3)

        let found = await BigItemScanner(env: sandbox.env, config: sandbox.config)
            .scan(minimumBytes: 1024 * 1024)
        let target = try #require(found.items.first { $0.path == chosen })

        let plan = Planner().plan(files: [target])
        let outcome = try sandbox.executor().apply(
            plan: plan, catalog: sandbox.catalog(), dryRun: false)

        #expect(outcome.quarantined.count == 1)
        #expect(outcome.quarantined.first?.ruleId == Executor.bigItemRuleId)
        #expect(!FileManager.default.fileExists(atPath: chosen), "選んだものは元の場所から消える")
        #expect(FileManager.default.fileExists(atPath: untouched), "選んでいないものには触れない")

        let restored = try sandbox.executor().undo(runId: outcome.runId)
        #expect(restored.restored.count == 1)
        #expect(FileManager.default.fileExists(atPath: chosen), "元の場所へ戻る")
    }

    @Test("移した記録が監査ログに残り、隔離庫の索引にも入る")
    func recordsWhatItMoved() async throws {
        let sandbox = try Sandbox()
        let target = try makeFile(sandbox, "Documents/work/big.bin", megabytes: 3)
        let item = try #require(
            await BigItemScanner(env: sandbox.env, config: sandbox.config)
                .scan(minimumBytes: 1024 * 1024).items.first { $0.path == target })

        let outcome = try sandbox.executor().apply(
            plan: Planner().plan(files: [item]), catalog: sandbox.catalog(), dryRun: false)

        let runs = QuarantineStore(root: sandbox.env.quarantineDir).loadIndex().runs
        #expect(runs.first?.entries.first?.originalPath == target)
        let records = sandbox.audit.read(since: nil, until: nil, action: .apply).records
        #expect(records.contains { $0.ruleId == Executor.bigItemRuleId && $0.path == target })
        #expect(outcome.reclaimedBytes >= 3 * 1024 * 1024)
    }

    @Test("ホーム直下のものは移さず、理由を付けて見送る")
    func refusesShallowTargets() async throws {
        let sandbox = try Sandbox()
        let shallow = try makeFile(sandbox, "toplevel.bin", megabytes: 3)
        let item = BigItem(
            path: shallow, name: "toplevel.bin", bytes: 3 * 1024 * 1024, fileCount: 1,
            isDirectory: false, modified: Date(), kind: .other, group: .file, marker: nil,
            adviceJa: "", advice: "")

        let outcome = try sandbox.executor().apply(
            plan: Planner().plan(files: [item]), catalog: sandbox.catalog(), dryRun: false)

        #expect(outcome.quarantined.isEmpty)
        #expect(outcome.skipped.first?.reason == "too-shallow")
        #expect(FileManager.default.fileExists(atPath: shallow), "見送ったものはそのまま残る")
        let records = sandbox.audit.read(since: nil, until: nil, action: .apply).records
        #expect(records.contains { $0.result == .skipped }, "見送りも記録に残す")
    }

    @Test("探している間、いまどこを見ているかが流れる")
    func reportsProgressWhileSearching() async throws {
        let sandbox = try Sandbox()
        try makeFile(sandbox, "Documents/a/big.bin", megabytes: 2)
        let box = ProgressBox()

        _ = await BigItemScanner(env: sandbox.env, config: sandbox.config)
            .scan(minimumBytes: 1024 * 1024, onProgress: box.handler)

        let events = box.events
        #expect(!events.isEmpty, "黙って待たせない")
        #expect(events.allSatisfy { $0.step == .measuring })
        #expect(events.allSatisfy { $0.total == 0 }, "総数が分からないうちは割合を作らない")
        #expect(events.contains { $0.path.hasSuffix("/Documents/a") })
    }

    @Test("やめると、そこまでの結果を返して止まる")
    func stopsWhenAsked() async throws {
        let sandbox = try Sandbox()
        try makeFile(sandbox, "Documents/big.bin", megabytes: 2)
        let token = CancelToken()
        token.cancel()

        let result = await BigItemScanner(env: sandbox.env, config: sandbox.config)
            .scan(minimumBytes: 1024 * 1024, isCancelled: token.check)

        #expect(result.interrupted, "「見つかりませんでした」と混同させない")
        #expect(result.items.isEmpty)
    }

    @Test("移すときも 1 件ずつ報せが出て、選んだ数と合う")
    func reportsProgressWhileMoving() async throws {
        let sandbox = try Sandbox()
        let first = try makeFile(sandbox, "Documents/one.bin", megabytes: 2)
        let second = try makeFile(sandbox, "Documents/two.bin", megabytes: 2)
        let found = await BigItemScanner(env: sandbox.env, config: sandbox.config)
            .scan(minimumBytes: 1024 * 1024)
        #expect(found.items.count == 2)

        let box = ProgressBox()
        let outcome = try sandbox.executor().apply(
            plan: Planner().plan(files: found.items), catalog: sandbox.catalog(), dryRun: false,
            onProgress: box.handler)

        #expect(outcome.quarantined.count == 2)
        let moving = box.events.filter { $0.step == .moving }
        #expect(moving.count == 2, "1 件ずつ報せが出る")
        #expect(moving.allSatisfy { $0.total == 2 }, "総数が最初から分かっている")
        #expect(Set(moving.map(\.path)) == Set([first, second]))
    }
}
