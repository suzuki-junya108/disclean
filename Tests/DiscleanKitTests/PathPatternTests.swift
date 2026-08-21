import Foundation
import Testing

@testable import DiscleanKit

@Suite("場所のひな形（* と ?）")
struct PathPatternTests {
    private func makeTree() throws -> String {
        let root = NSTemporaryDirectory() + "disclean-glob-" + UUID().uuidString
        let manager = FileManager.default
        for device in ["AAAA-1111", "BBBB-2222"] {
            try manager.createDirectory(
                atPath: root + "/Devices/\(device)/data/Containers/Data/Application/APP-1/Library/Caches",
                withIntermediateDirectories: true)
        }
        try manager.createDirectory(
            atPath: root + "/Devices/AAAA-1111/data/Containers/Data/Application/APP-2/Library/Caches",
            withIntermediateDirectories: true)
        // 隠しフォルダ。`*` では当たらないこと。
        try manager.createDirectory(atPath: root + "/Devices/.hidden", withIntermediateDirectories: true)
        return root
    }

    @Test("階層ごとに広げ、実在するものだけ返す")
    func expandsPerSegment() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let matches = PathPattern.expand(
            root + "/Devices/*/data/Containers/Data/Application/*/Library/Caches")
        #expect(matches.count == 3)
        #expect(matches.allSatisfy { $0.hasSuffix("/Library/Caches") })
        #expect(matches.contains { $0.contains("AAAA-1111") && $0.contains("APP-2") })
    }

    @Test("`*` は隠し項目に当たらない")
    func skipsHiddenEntries() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let matches = PathPattern.expand(root + "/Devices/*")
        #expect(matches.count == 2, "隠しフォルダは数えない")
        #expect(!matches.contains { $0.hasSuffix("/.hidden") })
    }

    @Test("当たらなければ空。ワイルドカードが無ければ実在確認だけ")
    func handlesMissing() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }

        #expect(PathPattern.expand(root + "/Devices/*/nowhere").isEmpty)
        #expect(PathPattern.expand(root + "/Devices").count == 1)
        #expect(PathPattern.expand(root + "/does-not-exist").isEmpty)
    }

    @Test("固定部分だけを取り出す（カタログ検証に使う）")
    func extractsStaticPrefix() {
        #expect(
            PathPattern.staticPrefix("~/Library/Developer/CoreSimulator/Devices/*/data")
                == "~/Library/Developer/CoreSimulator/Devices")
        #expect(PathPattern.staticPrefix("~/Library/Caches") == "~/Library/Caches")
        #expect(PathPattern.staticPrefix("~/*") == "~")
    }

    @Test("リンクは辿らない")
    func doesNotFollowSymlinks() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let outside = NSTemporaryDirectory() + "disclean-glob-outside-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: outside + "/Library/Caches", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: outside) }
        try FileManager.default.createSymbolicLink(
            atPath: root + "/Devices/LINK", withDestinationPath: outside)

        // リンク自身は名前として当たるが、その先の階層は辿らない。
        let deep = PathPattern.expand(root + "/Devices/*/Library/Caches")
        #expect(deep.isEmpty, "リンクの先の階層まで広げない")
    }
}
