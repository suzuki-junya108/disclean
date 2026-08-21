import Foundation
import Testing

@testable import DiscleanKit

@Suite("なかみを 1 段ずつ辿る")
@MainActor
struct InventoryBrowserTests {
    private func makeTree() throws -> String {
        let root = NSTemporaryDirectory() + "disclean-browse-" + UUID().uuidString
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/wheels", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/logs", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 5 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: root + "/wheels/numpy-2.1.0.whl"))
        try Data(repeating: 0x41, count: 1024 * 1024)
            .write(to: URL(fileURLWithPath: root + "/logs/install.log"))
        return root
    }

    private func session(roots: [InspectSession.Root]) -> InspectSession {
        InspectSession(
            title: "テスト", whatItIs: "これは何か", fate: "こうなる", undoable: true, roots: roots)
    }

    @Test("根が 1 つなら、開いた時点で中身が出る")
    func showsContentsForSingleRoot() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let browser = session(roots: [.init(path: root, label: root)])
        browser.start()
        await browser.waitForPendingWork()

        #expect(!browser.showsRootList)
        let names = try #require(browser.inventory?.entries.map(\.name))
        #expect(names == ["wheels", "logs"], "大きい順に並ぶ")
        #expect(browser.locationLabel == root)
    }

    @Test("フォルダをひらくと 1 段下がり、もどると戻る")
    func drillsDownAndBack() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let browser = session(roots: [.init(path: root, label: root)])
        browser.start()
        await browser.waitForPendingWork()

        let wheels = try #require(browser.inventory?.entries.first { $0.name == "wheels" })
        browser.open(wheels)
        await browser.waitForPendingWork()

        #expect(browser.canGoBack)
        #expect(browser.currentPath == root + "/wheels")
        #expect(browser.inventory?.entries.map(\.name) == ["numpy-2.1.0.whl"])
        #expect(browser.inventory?.entries.first?.kind == .archive)

        browser.back()
        await browser.waitForPendingWork()
        #expect(!browser.canGoBack)
        #expect(browser.inventory?.entries.count == 2, "根の中身に戻る")
    }

    @Test("ファイルはひらけない（1 段下がらない）")
    func doesNotDrillIntoFiles() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let browser = session(roots: [.init(path: root + "/logs", label: "logs")])
        browser.start()
        await browser.waitForPendingWork()

        let log = try #require(browser.inventory?.entries.first)
        browser.open(log)
        #expect(!browser.canGoBack)
    }

    @Test("根が複数なら、まず場所の一覧を出し、それぞれの大きさを測る")
    func listsRootsWithSizes() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let browser = session(roots: [
            .init(path: root + "/wheels", label: "~/wheels"),
            .init(path: root + "/logs", label: "~/logs"),
        ])
        browser.start()
        await browser.waitForPendingWork()

        #expect(browser.showsRootList)
        #expect(browser.inventory == nil, "まだ中身は出さない")
        let sizes = browser.roots.map(\.bytes)
        #expect(sizes.allSatisfy { ($0 ?? 0) > 0 })

        browser.open(browser.roots[0])
        await browser.waitForPendingWork()
        #expect(browser.inventory?.entries.first?.name == "numpy-2.1.0.whl")

        browser.back()
        await browser.waitForPendingWork()
        #expect(browser.showsRootList, "根の一覧に戻る")
    }
}
