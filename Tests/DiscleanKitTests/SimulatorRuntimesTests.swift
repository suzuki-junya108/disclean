import Foundation
import Testing

@testable import DiscleanKit

@Suite("シミュレータ本体（SimulatorRuntime）の読み取り")
struct SimulatorRuntimesTests {
    private let imagesJSON = """
        {
          "00E5C5F8-59D9-4AE7-9DB5-3B691935C812": {
            "build": "23B86", "deletable": true,
            "identifier": "00E5C5F8-59D9-4AE7-9DB5-3B691935C812",
            "lastUsedAt": "2026-08-06T11:22:27Z",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
            "sizeBytes": 8344869917, "state": "Ready", "version": "26.1"
          },
          "70224A2C-559D-4C8B-83A3-DD2B8060185C": {
            "build": "23B5059e", "deletable": true,
            "identifier": "70224A2C-559D-4C8B-83A3-DD2B8060185C",
            "lastUsedAt": "2025-10-27T09:37:24Z",
            "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
            "sizeBytes": 8700000000, "state": "Ready", "version": "26.1"
          }
        }
        """

    private let listJSON = """
        {
          "runtimes": [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "buildversion": "23B86"},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "buildversion": "23B5059e"},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-6", "buildversion": "22G86"}
          ],
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [{}, {}, {}],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [{}]
          }
        }
        """

    @Test("simctl runtime list -j の出力から本体の一覧を読む")
    func parsesImages() throws {
        let images = try #require(SimulatorRuntimes.parseImages(imagesJSON))
        #expect(images.count == 2)
        let beta = try #require(images.first { $0.build == "23B5059e" })
        #expect(beta.identifier == "70224A2C-559D-4C8B-83A3-DD2B8060185C")
        #expect(beta.sizeBytes == 8_700_000_000)
        #expect(beta.lastUsedAt == ISO8601DateFormatter().date(from: "2025-10-27T09:37:24Z"))
        #expect(beta.name(japanese: true) == "iOS 26.1（23B5059e）")
        #expect(beta.name(japanese: false) == "iOS 26.1 (23B5059e)")
    }

    @Test("読めない出力は nil（0 件と区別する）")
    func unreadableImagesAreNil() {
        #expect(SimulatorRuntimes.parseImages("not json") == nil)
    }

    @Test("dry-run の Would delete 行だけから UUID を拾う")
    func parsesDryRun() {
        let output = """
            Would delete P: 70224a2c-559d-4c8b-83a3-dd2b8060185c iOS (26.1 - 23B5059e) (Ready)
            Note: 00E5C5F8-59D9-4AE7-9DB5-3B691935C812 is still in use
            """
        #expect(SimulatorRuntimes.parseWouldDelete(output) == ["70224A2C-559D-4C8B-83A3-DD2B8060185C"])
        #expect(SimulatorRuntimes.parseWouldDelete("No matching images found to delete").isEmpty)
    }

    @Test("--dry-run の無いコマンドは、量を測るためであっても実行しない")
    func refusesCommandsWithoutDryRun() throws {
        let marker = NSTemporaryDirectory() + "disclean-dryrun-guard-" + UUID().uuidString
        let result = SimulatorRuntimes.targets(
            dryRun: CommandSpec(executable: "/usr/bin/touch", arguments: [marker]),
            cacheRoots: [], timeoutSeconds: 5)
        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: marker), "実行されていれば印のファイルができている")
    }

    @Test("同じ版の別ビルドが残るなら、端末は使えなくならない")
    func devicesKeepWorkingWhenAnotherBuildRemains() throws {
        let images = try #require(SimulatorRuntimes.parseImages(imagesJSON))
        let beta = images.filter { $0.build == "23B5059e" }
        let losing = try #require(SimulatorRuntimes.devicesLosingRuntime(targets: beta, listJSON: listJSON))
        #expect(losing.isEmpty)
    }

    @Test("版のビルドがすべて消えるなら、その版の端末の数を 1 回だけ数える")
    func countsDevicesOnceWhenVersionDisappears() throws {
        let images = try #require(SimulatorRuntimes.parseImages(imagesJSON))
        let losing = try #require(SimulatorRuntimes.devicesLosingRuntime(targets: images, listJSON: listJSON))
        #expect(losing.values.reduce(0, +) == 3, "同じ 3 台を 2 本ぶん数えない")
        #expect(losing.count == 1)
    }

    @Test("共有キャッシュは、ホストの OS ビルドごとのフォルダをすべて足す")
    func sumsSharedCachesAcrossHostBuilds() throws {
        let root = NSTemporaryDirectory() + "disclean-dyld-" + UUID().uuidString
        let name = "com.apple.CoreSimulator.SimRuntime.iOS-26-1.23B5059e"
        let fm = FileManager.default
        for host in ["25F84", "25G10"] {
            try fm.createDirectory(atPath: root + "/\(host)/\(name)", withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 1024 * 1024)
                .write(to: URL(fileURLWithPath: root + "/\(host)/\(name)/cache.bin"))
        }
        // 別の本体のキャッシュは数えない
        try fm.createDirectory(atPath: root + "/25F84/other.23B86", withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4 * 1024 * 1024)
            .write(to: URL(fileURLWithPath: root + "/25F84/other.23B86/cache.bin"))

        let images = try #require(SimulatorRuntimes.parseImages(imagesJSON))
        let beta = try #require(images.first { $0.build == "23B5059e" })
        let expected =
            DirectoryMeter.measure(path: root + "/25F84/\(name)").bytes
            + DirectoryMeter.measure(path: root + "/25G10/\(name)").bytes
        #expect(SimulatorRuntimes.cacheBytes(for: beta, roots: [root]) == expected)
        #expect(expected >= 2 * 1024 * 1024)
    }

    @Test("消す前に読む 1 行に、名前・量・最後に使った日・巻き込まれるものが入る")
    func describesWhatIsLost() throws {
        let images = try #require(SimulatorRuntimes.parseImages(imagesJSON))
        let beta = try #require(images.first { $0.build == "23B5059e" })
        let target = SimulatorRuntimeTarget(
            runtime: beta, cacheBytes: 3_800_000_000, devicesLosingRuntime: 13, alsoOutdated: true)
        let ja = target.describe(japanese: true)
        #expect(ja.contains("iOS 26.1（23B5059e）"))
        #expect(ja.contains("共有キャッシュ"))
        #expect(ja.contains("最後に使った日 2025-10-2"))
        #expect(ja.contains("端末 13 台が使えなくなります"))
        #expect(ja.contains("1 回ぶん"))
        #expect(target.totalBytes == 12_500_000_000)

        let quiet = SimulatorRuntimeTarget(
            runtime: beta, cacheBytes: 0, devicesLosingRuntime: 0, alsoOutdated: false)
        let en = quiet.describe(japanese: false)
        #expect(!en.contains("device"), "巻き込まれる端末が無いなら書かない")
        #expect(!en.contains("shared cache"))
    }
}
