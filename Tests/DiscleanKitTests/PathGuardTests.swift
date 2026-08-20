import Foundation
import Testing
@testable import DiscleanKit

private func makeGuard(home: String, excluded: [String] = ["~/Sync"]) -> PathGuard {
    PathGuard(
        home: home, stateDir: home + "/.local/state/disclean",
        configDir: home + "/.config/disclean", excludedPaths: excluded)
}

@Suite("PathGuard SG-01〜SG-09")
struct PathGuardTests {
    let home = "/Users/tester"

    @Test("SG-01 ホーム外は拒否する")
    func outsideHome() {
        #expect(makeGuard(home: home).validateRulePath("/opt/data/cache") == .outsideHome)
        #expect(makeGuard(home: home).validateRulePath("/Users/other/Library/Caches") == .outsideHome)
    }

    @Test("SG-02 ホーム直下の 1 階層は浅すぎる")
    func tooShallow() {
        #expect(makeGuard(home: home).validateRulePath("~/Library") == .tooShallow)
        #expect(makeGuard(home: home).validateRulePath("~/Library/Caches") == nil)
    }

    @Test(
        "SG-03 システム領域とルートは拒否する",
        arguments: [
            "/", "/System/Library/Caches", "/Library/Caches", "/private/var/log", "/usr/local/lib", "/bin",
        ])
    func forbiddenRoots(path: String) {
        #expect(makeGuard(home: home).validateRulePath(path) == .forbiddenRoot)
    }

    @Test("SG-05 状態・設定ディレクトリ自身は対象にしない")
    func selfReferential() {
        let guardian = makeGuard(home: home)
        #expect(guardian.validateRulePath("~/.local/state/disclean/quarantine") == .selfReferential)
        #expect(guardian.validateRulePath("~/.config/disclean/rules.d") == .selfReferential)
    }

    @Test("SG-06 除外パス配下は対象にしない")
    func excluded() {
        #expect(makeGuard(home: home).validateRulePath("~/Sync/disclean/.build") == .excluded)
        #expect(makeGuard(home: home, excluded: []).validateRulePath("~/Sync/disclean/.build") == nil)
    }

    @Test("SG-04 シンボリックリンクは辿らず拒否する")
    func symlink() throws {
        let tmp = try TempHome()
        let target = tmp.home + "/Library/Caches/real"
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        let link = tmp.home + "/Library/Caches/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        let guardian = makeGuard(home: tmp.home, excluded: [])
        #expect(guardian.validateForRemoval(path: link, minAgeDays: nil) == .symlink)
        #expect(guardian.validateForRemoval(path: target, minAgeDays: nil) == nil)
    }

    @Test("SG-09 更新が新しすぎるものは触らない")
    func tooRecent() throws {
        let tmp = try TempHome()
        let path = tmp.home + "/Library/Caches/fresh"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let guardian = makeGuard(home: tmp.home, excluded: [])
        #expect(guardian.validateForRemoval(path: path, minAgeDays: 3) == .tooRecent)
        #expect(guardian.validateForRemoval(path: path, minAgeDays: 0) == nil)
    }

    @Test("存在しないパスは not-found")
    func notFound() throws {
        let tmp = try TempHome()
        let guardian = makeGuard(home: tmp.home, excluded: [])
        #expect(guardian.validateForRemoval(path: tmp.home + "/Library/Caches/nope", minAgeDays: nil) == .notFound)
    }

    @Test("SG-08 別ボリュームなら移動しない")
    func crossVolume() throws {
        let tmp = try TempHome()
        let path = tmp.home + "/Library/Caches/item"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let guardian = makeGuard(home: tmp.home, excluded: [])
        // /dev は必ず別ボリューム（devfs）。
        #expect(guardian.validateForRemoval(path: path, minAgeDays: nil, sameVolumeAs: "/dev") == .crossVolume)
    }

    @Test("~ 展開と正規化")
    func expansion() {
        #expect(Expand.tilde("~/Library", home: "/Users/tester") == "/Users/tester/Library")
        #expect(Expand.tilde("~", home: "/Users/tester") == "/Users/tester")
        #expect(Expand.tilde("/abs/path", home: "/Users/tester") == "/abs/path")
        #expect(PathGuard.normalize("/Users/tester/") == "/Users/tester")
        #expect(PathGuard.isUnder("/a/b/c", "/a/b"))
        #expect(!PathGuard.isUnder("/a/bc", "/a/b"))
    }
}

/// テスト用の一時ホーム。実ユーザーのディレクトリには一切触れない。
struct TempHome {
    let home: String

    init() throws {
        let base = NSTemporaryDirectory() + "disclean-test-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: base + "/Library/Caches", withIntermediateDirectories: true)
        home = base
    }

    var env: DiscleanEnvironment {
        DiscleanEnvironment(environment: [
            "HOME": home,
            "DISCLEAN_STATE_DIR": home + "/state",
            "DISCLEAN_CONFIG_DIR": home + "/config",
            "DISCLEAN_LANG": "en",
        ])
    }
}
