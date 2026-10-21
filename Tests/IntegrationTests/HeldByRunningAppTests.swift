import AppKit
import Foundation
import Testing
@testable import DiscleanKit

/// いま起動しているアプリの bundle ID。GUI のない環境では取れないので、そのときは試験を飛ばす。
private let runningBundleId = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).first

@Suite("アプリが起動中で見送ったものも量を測る")
struct HeldByRunningAppTests {
    @Test(
        "起動中のアプリのデータは候補に入れないが、量は残す",
        .enabled(if: runningBundleId != nil, "起動中のアプリが 1 つも無い環境"))
    func keepsSizeWhileHeld() async throws {
        let bundleId = try #require(runningBundleId)
        let sandbox = try Sandbox()
        try sandbox.makeFixtureFiles()
        let rule: [String: Any] = [
            "id": "held-fixture", "title": "held", "tier": "B", "kind": "directory",
            "paths": ["~/Library/Caches/fixture"], "whatIsLost": "test data",
            "requiresQuitApps": [bundleId],
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-held.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["held-fixture"])
        let item = try #require(result.items.first { $0.ruleId == "held-fixture" })

        #expect(item.state == .skipped)
        #expect(item.reason == "app-running:\(bundleId)")
        #expect(item.bytes >= 3 * 1024 * 1024, "終了すれば空く量が分かるように、測った量を残す")
        #expect(item.fileCount == 3)
        #expect(result.heldByRunningApp.map(\.ruleId) == ["held-fixture"])
        #expect(result.readyItems.isEmpty, "起動中のあいだは選べない")
        #expect(result.totalBytes == 0, "合計には入れない")
    }

    @Test(
        "起動中でも中身が空なら、空だったと伝える",
        .enabled(if: runningBundleId != nil, "起動中のアプリが 1 つも無い環境"))
    func emptyIsNotHeld() async throws {
        let bundleId = try #require(runningBundleId)
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(
            atPath: sandbox.home + "/Library/Caches/fixture", withIntermediateDirectories: true)
        let rule: [String: Any] = [
            "id": "held-empty", "title": "held", "tier": "B", "kind": "directory",
            "paths": ["~/Library/Caches/fixture"], "whatIsLost": "test data",
            "requiresQuitApps": [bundleId],
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-held.json"))

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["held-empty"])
        let item = try #require(result.items.first { $0.ruleId == "held-empty" })

        #expect(item.reason == "empty")
        #expect(result.heldByRunningApp.isEmpty)
    }

    @Test("理由から bundle ID を取り出す")
    func parsesBundleId() {
        #expect(SkipReason.runningAppBundleId("app-running:com.apple.dt.Xcode") == "com.apple.dt.Xcode")
        #expect(SkipReason.runningAppBundleId("empty") == nil)
        #expect(SkipReason.runningAppBundleId(nil) == nil)
    }
}
