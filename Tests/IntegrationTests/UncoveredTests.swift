import Foundation
import Testing

@testable import DiscleanKit

@Suite("まだ見ていない大きな場所")
struct UncoveredTests {
    private func fill(_ path: String, megabytes: Int) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: megabytes * 1024 * 1024)
            .write(to: URL(fileURLWithPath: path + "/blob.bin"))
    }

    private func writeRule(_ sandbox: Sandbox, id: String, path: String) throws {
        let rule: [String: Any] = [
            "id": id, "title": id, "tier": "A", "kind": "directory",
            "paths": [path], "whatIsLost": "x",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-\(id).json"))
    }

    /// `~/Library/Caches` は同梱ルールが丸ごと見ているため、ここでは
    /// ルールの外にある `Application Support` で確かめる。
    @Test("ルールが見ていない大きな場所だけを、消さずに報告する")
    func reportsOnlyUncovered() async throws {
        let sandbox = try Sandbox()
        let base = sandbox.home + "/Library/Application Support"
        try fill(base + "/CoveredApp", megabytes: 6)
        try fill(base + "/UnknownApp", megabytes: 8)
        try fill(base + "/TinyApp", megabytes: 1)
        try writeRule(sandbox, id: "covered", path: "~/Library/Application Support/CoveredApp")

        let result = await UncoveredScanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), minimumBytes: 4 * 1024 * 1024)
        let names = result.places.map { ($0.path as NSString).lastPathComponent }

        #expect(names.contains("UnknownApp"))
        #expect(!names.contains("CoveredApp"), "ルールが見ている場所は出さない")
        #expect(!names.contains("TinyApp"), "しきい値より小さいものは出さない")

        var st = stat()
        #expect(lstat(base + "/UnknownApp/blob.bin", &st) == 0, "読むだけで消さない")
    }

    @Test("一部だけルールが見ている場所は、1 段下りて残りを出す")
    func descendsIntoPartiallyCovered() async throws {
        let sandbox = try Sandbox()
        try fill(sandbox.home + "/.tooling/known", megabytes: 6)
        try fill(sandbox.home + "/.tooling/unknown", megabytes: 7)
        try writeRule(sandbox, id: "known", path: "~/.tooling/known")

        let result = await UncoveredScanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), minimumBytes: 4 * 1024 * 1024)
        let paths = result.places.map(\.path)

        #expect(paths.contains { $0.hasSuffix("/.tooling/unknown") })
        #expect(!paths.contains { $0.hasSuffix("/.tooling") }, "親ごと出すと、中の内訳が分からない")
        #expect(!paths.contains { $0.hasSuffix("/.tooling/known") })
    }

    @Test("自分の隔離庫は報告しない")
    func neverReportsItsOwnStore() async throws {
        let sandbox = try Sandbox()
        try fill(sandbox.env.quarantineDir + "/01TEST/rule", megabytes: 9)

        let result = await UncoveredScanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), minimumBytes: 1024 * 1024)
        #expect(!result.places.contains { $0.path.hasPrefix(sandbox.env.stateDir) })
    }

    @Test("除外した場所は報告しない")
    func respectsExclusions() async throws {
        let sandbox = try Sandbox(excluded: ["~/Library/Caches/Private"])
        try fill(sandbox.home + "/Library/Caches/Private", megabytes: 8)

        let result = await UncoveredScanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), minimumBytes: 4 * 1024 * 1024)
        #expect(!result.places.contains { $0.path.hasSuffix("/Private") })
    }
}
