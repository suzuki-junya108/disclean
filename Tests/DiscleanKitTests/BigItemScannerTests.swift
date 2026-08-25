import Foundation
import Testing

@testable import DiscleanKit

@Suite("大きいもの探し: 部品はまとめ、書類はそのまま見せる")
struct BigItemScannerTests {
    /// 一時ディレクトリをホームに見立てた実行環境。実ユーザーには触れない。
    private struct Home {
        let path: String
        let env: DiscleanEnvironment
        let config: Config

        init(excluded: [String] = []) throws {
            let base = NSTemporaryDirectory() + "disclean-big-" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
            path = base
            env = DiscleanEnvironment(environment: [
                "HOME": base,
                "DISCLEAN_STATE_DIR": base + "/state",
                "DISCLEAN_CONFIG_DIR": base + "/config",
                "DISCLEAN_LANG": "en",
            ])
            config = Config(concurrency: 2, excludedPaths: excluded, autoUpdate: false)
        }

        func scanner() -> BigItemScanner { BigItemScanner(env: env, config: config) }

        @discardableResult
        func makeFile(_ relative: String, megabytes: Int) throws -> String {
            let full = path + "/" + relative
            let parent = (full as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: megabytes * 1024 * 1024)
                .write(to: URL(fileURLWithPath: full))
            return full
        }

        func remove() { try? FileManager.default.removeItem(atPath: path) }
    }

    private let threshold: Int64 = 1024 * 1024  // 1MiB

    @Test("部品置き場は 1 件にまとまり、中のファイルは個別に出ない")
    func groupsPartsDirectories() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.makeFile("Documents/proj/node_modules/a/big.bin", megabytes: 3)
        try home.makeFile("Documents/proj/node_modules/b/big.bin", megabytes: 2)

        let result = await home.scanner().scan(minimumBytes: threshold)
        let paths = result.items.map(\.path)
        #expect(paths == [home.path + "/Documents/proj/node_modules"], "入れ物 1 件だけが出る")
        let item = try #require(result.items.first)
        #expect(item.group == .parts)
        #expect(item.marker == "node_modules")
        #expect(item.fileCount == 2, "中のファイル数は数える")
        #expect(item.bytes >= 5 * 1024 * 1024)
        #expect(item.adviceJa.contains("入れ直せます"), "消すとどうなるかを添える")
    }

    @Test("アプリなどのひとかたまりは、中へ下りずに 1 件として出す")
    func groupsBundles() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.makeFile("Documents/Big.app/Contents/MacOS/binary", megabytes: 4)

        let result = await home.scanner().scan(minimumBytes: threshold)
        let item = try #require(result.items.first)
        #expect(result.items.count == 1)
        #expect(item.path == home.path + "/Documents/Big.app")
        #expect(item.group == .bundle)
        #expect(item.marker == ".app")
    }

    @Test("しきい値に満たないものは出さない")
    func skipsSmallThings() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.makeFile("Documents/small.bin", megabytes: 1)
        try home.makeFile("Documents/large.bin", megabytes: 6)

        let result = await home.scanner().scan(minimumBytes: 5 * 1024 * 1024)
        #expect(result.items.map(\.name) == ["large.bin"])
        #expect(result.scannedEntries >= 2, "見た件数は数える（0 件でも探したことが分かる）")
    }

    @Test("同じ実体を指すハードリンクは 1 回だけ数える")
    func countsHardLinksOnce() async throws {
        let home = try Home()
        defer { home.remove() }
        let original = try home.makeFile("Documents/movie.bin", megabytes: 3)
        try FileManager.default.linkItem(atPath: original, toPath: home.path + "/Documents/copy.bin")

        let result = await home.scanner().scan(minimumBytes: threshold)
        #expect(result.items.count == 1, "同じ実体を二重に数えない")
    }

    @Test("シンボリックリンクは辿らず、実体だけを出す")
    func ignoresSymlinks() async throws {
        let home = try Home()
        defer { home.remove() }
        let original = try home.makeFile("Documents/real/movie.bin", megabytes: 3)
        try FileManager.default.createSymbolicLink(
            atPath: home.path + "/Documents/link.bin", withDestinationPath: original)
        try FileManager.default.createSymbolicLink(
            atPath: home.path + "/Documents/loop", withDestinationPath: home.path + "/Documents")

        let result = await home.scanner().scan(minimumBytes: threshold)
        #expect(result.items.map(\.path) == [original], "リンクは出さず、輪にもはまらない")
    }

    @Test("ホームのすぐ下のファイルと隠しフォルダは、探す範囲に入れない")
    func staysInVisibleFolders() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.makeFile("toplevel.bin", megabytes: 4)
        try home.makeFile(".hidden/inside.bin", megabytes: 4)
        try home.makeFile("Documents/kept.bin", megabytes: 4)

        let result = await home.scanner().scan(minimumBytes: threshold)
        #expect(result.items.map(\.name) == ["kept.bin"])
    }

    @Test("~/Library は既定では見ない。頼まれたときだけ見る")
    func libraryIsOptional() async throws {
        let home = try Home()
        defer { home.remove() }
        try home.makeFile("Library/Caches/app/blob.bin", megabytes: 4)

        let quiet = await home.scanner().scan(minimumBytes: threshold)
        #expect(quiet.items.isEmpty)
        #expect(!quiet.roots.contains { $0.hasSuffix("/Library") })

        let loud = await home.scanner().scan(minimumBytes: threshold, includeLibrary: true)
        #expect(loud.items.count == 1)
    }

    @Test("除外した場所と、自分の保存先は見に行かない")
    func respectsExclusionsAndOwnState() async throws {
        let home = try Home(excluded: ["~/Documents/Private"])
        defer { home.remove() }
        try home.makeFile("Documents/Private/secret.bin", megabytes: 4)
        try home.makeFile("state/quarantine/RUN/moved.bin", megabytes: 4)
        try home.makeFile("Documents/kept.bin", megabytes: 4)

        let result = await home.scanner().scan(minimumBytes: threshold)
        #expect(result.items.map(\.name) == ["kept.bin"])
    }

    @Test("多いときは大きいものだけを出し、打ち切ったことを伝える")
    func truncatesAndSaysSo() async throws {
        let home = try Home()
        defer { home.remove() }
        for index in 0..<5 {
            try home.makeFile("Documents/file-\(index).bin", megabytes: 2 + index)
        }

        let result = await home.scanner().scan(minimumBytes: threshold, limit: 2)
        #expect(result.items.count == 2)
        #expect(result.truncated)
        #expect(result.items.map(\.bytes) == result.items.map(\.bytes).sorted(by: >), "大きい順")
    }
}
