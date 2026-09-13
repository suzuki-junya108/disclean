import Foundation
import Testing

@testable import DiscleanKit

@Suite("システムデータの中身（見るだけ）")
struct SystemDataTests {
    private func fill(_ path: String, megabytes: Int) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: megabytes * 1024 * 1024)
            .write(to: URL(fileURLWithPath: path + "/blob.bin"))
    }

    private func locations(base: String, simctl: String?) -> SystemDataLocations {
        SystemDataLocations(
            simctl: simctl,
            simulatorCacheRoots: [base + "/fake-simctl/dyld"],
            sleepImage: base + "/vm/sleepimage",
            softwareUpdates: [.init(base + "/Updates")],
            systemLogs: [.init(base + "/diagnostics"), .init(base + "/uuidtext")],
            fileProvider: [.init(base + "/FileProvider"), .init(base + "/T/com.apple.fileproviderd")],
            userTemporary: [.init(base + "/T", excluding: ["com.apple.fileproviderd"]), .init(base + "/C")],
            swapUsedBytes: { 7_000_000 },
            capacity: {
                CapacitySample(strictBytes: 10_000_000, importantBytes: 25_000_000, snapshotCount: 2)
            })
    }

    /// 測った場所のファイル一覧（パスと大きさ）。読むだけで何も変わらないことを確かめる。
    private func snapshot(_ root: String) -> [String: Int64] {
        var files: [String: Int64] = [:]
        let enumerator = FileManager.default.enumerator(atPath: root)
        while let relative = enumerator?.nextObject() as? String {
            var st = stat()
            if lstat(root + "/" + relative, &st) == 0 { files[relative] = Int64(st.st_size) }
        }
        return files
    }

    @Test("場所ごとに測り、同期の作業領域を一時置き場と二重に数えない")
    func measuresEachPlaceOnce() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/system"
        try fill(base + "/Updates/047-91568", megabytes: 3)
        try fill(base + "/diagnostics/Persist", megabytes: 2)
        try fill(base + "/T/com.apple.fileproviderd", megabytes: 5)
        try fill(base + "/T/other-app", megabytes: 1)
        try fill(base + "/C/cache", megabytes: 1)
        try FileManager.default.createDirectory(atPath: base + "/vm", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 1024 * 1024).write(to: URL(fileURLWithPath: base + "/vm/sleepimage"))

        let before = snapshot(base)
        let result = await SystemDataProbe(env: sandbox.env, locations: locations(base: base, simctl: nil)).scan()
        let byKind = Dictionary(uniqueKeysWithValues: result.items.map { ($0.kind, $0) })

        #expect(result.items.count == SystemDataItem.Kind.allCases.count, "黙って項目を落とさない")
        let updates = try #require(byKind[.softwareUpdates])
        #expect(updates.state == .measured)
        #expect(updates.bytes == DirectoryMeter.measure(path: base + "/Updates").bytes)

        let provider = try #require(byKind[.fileProvider])
        let temporary = try #require(byKind[.userTemporary])
        let providerBytes = DirectoryMeter.measure(path: base + "/T/com.apple.fileproviderd").bytes
        #expect(provider.bytes == providerBytes)
        #expect(
            temporary.bytes
                == DirectoryMeter.measure(path: base + "/T/other-app").bytes
                + DirectoryMeter.measure(path: base + "/C").bytes,
            "同期の作業領域は一時置き場から除く")

        #expect(byKind[.swap]?.bytes == 7_000_000)
        let purgeable = try #require(byKind[.purgeable])
        #expect(purgeable.bytes == 15_000_000)
        #expect(purgeable.details.contains { $0.contains("2") })

        let runtimes = try #require(byKind[.simulatorRuntimes])
        #expect(runtimes.state == .absent, "Xcode が無い Mac では「なし」")

        let logs = try #require(byKind[.systemLogs])
        #expect(logs.state == .measured, "片方（uuidtext）が無くても、ある方を測る")

        #expect(snapshot(base) == before, "読むだけで、何も変えない")
    }

    @Test("すべての項目に「消さない理由」と「減らし方」がある")
    func everyItemExplainsItself() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/system"
        let result = await SystemDataProbe(env: sandbox.env, locations: locations(base: base, simctl: nil)).scan()
        for item in result.items {
            #expect(!item.text.title.isEmpty)
            #expect(!item.text.whyNotDeleted.isEmpty, "\(item.kind.rawValue)")
            #expect(!item.text.howToReduce.isEmpty, "\(item.kind.rawValue)")
        }
        for kind in SystemDataItem.Kind.allCases {
            #expect(!SystemDataTexts.text(kind, japanese: true).whyNotDeleted.isEmpty)
        }
    }

    @Test("無い場所は「なし」、量の分からないものと一緒に後ろへ回す")
    func ordersMeasuredFirst() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/system"
        try fill(base + "/Updates/x", megabytes: 1)
        var places = locations(base: base, simctl: nil)
        places.swapUsedBytes = { nil }

        let result = await SystemDataProbe(env: sandbox.env, locations: places).scan()
        let states = result.items.map(\.state)
        let firstNotMeasured = states.firstIndex { $0 != .measured } ?? states.count
        #expect(states[..<firstNotMeasured].allSatisfy { $0 == .measured })
        #expect(result.items.first { $0.kind == .swap }?.state == .unknown)
        #expect(result.items.first { $0.kind == .swap }?.bytes == nil, "分からない量を 0 にしない")
    }

    @Test("読めない場所は「読めません」として、0 バイトと区別する")
    func unreadableIsBlocked() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/system"
        try fill(base + "/Updates/locked", megabytes: 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: base + "/Updates")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base + "/Updates") }

        let result = await SystemDataProbe(env: sandbox.env, locations: locations(base: base, simctl: nil)).scan()
        let updates = try #require(result.items.first { $0.kind == .softwareUpdates })
        #expect(updates.state == .blocked)
        #expect(updates.bytes == nil)
        #expect(result.blocked)
    }

    @Test("シミュレータ本体は simctl の一覧と共有キャッシュを合わせて測る")
    func measuresRuntimesThroughSimctl() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home
        let fake = try FakeSimctl(base: base)
        try fake.addImage(
            id: "70224A2C-559D-4C8B-83A3-DD2B8060185C", build: "23B5059e", sizeBytes: 5_000_000, cacheMegabytes: 2,
            target: false)

        let result = await SystemDataProbe(env: sandbox.env, locations: locations(base: base, simctl: fake.executable))
            .scan()
        let runtimes = try #require(result.items.first { $0.kind == .simulatorRuntimes })
        #expect(runtimes.state == .measured)
        #expect(runtimes.bytes == 5_000_000 + DirectoryMeter.measure(path: fake.dyldRoot).bytes)
        #expect(runtimes.details.contains { $0.contains("23B5059e") })
        #expect(fake.imageExists("70224A2C-559D-4C8B-83A3-DD2B8060185C"), "見るだけで消さない")
    }

    @Test("1 項目ずつ進みぐあいを流し、最後は全件おわりになる")
    func reportsProgressPerItem() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/system"
        let collected = ProgressCollector()
        _ = await SystemDataProbe(env: sandbox.env, locations: locations(base: base, simctl: nil))
            .scan(onProgress: { collected.append($0) })
        let steps = collected.values
        let total = SystemDataItem.Kind.allCases.count
        #expect(steps.first?.step == .counting)
        #expect(steps.filter { $0.step == .measuring && $0.completed == $0.total }.count == 1)
        #expect(steps.last?.completed == total)
        #expect(steps.allSatisfy { $0.total == total })
    }

    @Test("途中でやめたら、やめたと返す")
    func stopsWhenCancelled() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/system"
        let result = await SystemDataProbe(env: sandbox.env, locations: locations(base: base, simctl: nil))
            .scan(isCancelled: { true })
        #expect(result.interrupted)
        #expect(result.items.isEmpty)
    }
}

/// 別スレッドから届く進みぐあいを貯める。
final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [WorkProgress] = []

    func append(_ progress: WorkProgress) {
        lock.lock()
        stored.append(progress)
        lock.unlock()
    }

    var values: [WorkProgress] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
