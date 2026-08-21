import Foundation
import Testing

@testable import DiscleanKit

@Suite("中身の一覧: 何が入っているかを 1 段ずつ見せる")
struct FileInventoryTests {
    private func makeTree() throws -> String {
        let root = NSTemporaryDirectory() + "disclean-inv-" + UUID().uuidString
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/packages", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 3 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: root + "/packages/big.tgz"))
        try Data(repeating: 0x41, count: 512 * 1024)
            .write(to: URL(fileURLWithPath: root + "/packages/small.whl"))
        try Data(repeating: 0x41, count: 1024 * 1024)
            .write(to: URL(fileURLWithPath: root + "/install.log"))
        try Data(repeating: 0x41, count: 4096)
            .write(to: URL(fileURLWithPath: root + "/0a1b2c3d4e5f60718293"))
        return root
    }

    @Test("大きい順に並び、フォルダは中身を合計する")
    func ordersBySizeAndSumsFolders() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let inventory = FileInventory.list(paths: [root])
        let names = inventory.entries.map(\.name)
        #expect(names.first == "packages", "いちばん大きいのは中身 3.5MB のフォルダ")
        #expect(names.contains("install.log"))

        let packages = try #require(inventory.entries.first { $0.name == "packages" })
        #expect(packages.isDirectory)
        #expect(packages.bytes >= 3 * 1024 * 1024 + 512 * 1024)
        #expect(packages.fileCount == 2)
        #expect(inventory.totalFiles == 4, "フォルダの中のファイルも数える")
        #expect(!inventory.notFound)
    }

    @Test("種類を名前から言い当てる")
    func inferKinds() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let inventory = FileInventory.list(paths: [root + "/packages", root])
        let byName = Dictionary(uniqueKeysWithValues: inventory.entries.map { ($0.name, $0.kind) })
        #expect(byName["big.tgz"] == .archive)
        #expect(byName["small.whl"] == .archive)
        #expect(byName["install.log"] == .log)
        #expect(byName["0a1b2c3d4e5f60718293"] == .contentBlob, "拡張子の無い 16 進名はキャッシュの実体")
        #expect(byName["packages"] == .folder)
    }

    @Test("多すぎるときは大きいものだけ見せ、残りの件数を伝える")
    func limitsAndReportsHidden() throws {
        let root = NSTemporaryDirectory() + "disclean-inv-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        for index in 0..<12 {
            try Data(repeating: 0x41, count: (index + 1) * 4096)
                .write(to: URL(fileURLWithPath: root + "/file-\(index).bin"))
        }

        let inventory = FileInventory.list(paths: [root], limit: 5)
        #expect(inventory.entries.count == 5)
        #expect(inventory.hiddenCount == 7)
        #expect(inventory.entries.first?.name == "file-11.bin")
        #expect(inventory.totalFiles == 12, "合計は隠した分も含む")
    }

    @Test("リンクは辿らず、リンク自身として見せる")
    func doesNotFollowSymlinks() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createSymbolicLink(
            atPath: root + "/link-to-packages", withDestinationPath: root + "/packages")

        let inventory = FileInventory.list(paths: [root])
        let link = try #require(inventory.entries.first { $0.name == "link-to-packages" })
        #expect(link.isSymlink)
        #expect(!link.isDirectory)
        #expect(link.bytes < 64 * 1024, "リンク先の大きさを数えない")
    }

    @Test("場所が無ければ、無いと言う")
    func reportsMissingPath() {
        let inventory = FileInventory.list(paths: ["/nonexistent/disclean/place"])
        #expect(inventory.notFound)
        #expect(inventory.entries.isEmpty)
    }
}
