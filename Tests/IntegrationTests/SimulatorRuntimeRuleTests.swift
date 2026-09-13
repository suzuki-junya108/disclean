import Foundation
import Testing

@testable import DiscleanKit

/// 本物の `xcrun simctl` の代わりに、同じ引数に同じ形で答える小さな台本を置く。
/// 本体の一覧・dry-run・削除を、一時ディレクトリの中だけで再現する。
struct FakeSimctl {
    let root: String
    var executable: String { root + "/xcrun" }
    var dyldRoot: String { root + "/dyld" }

    static let script = """
        #!/bin/bash
        DIR="$(cd "$(dirname "$0")" && pwd)"
        if [ "$1 $2 $3" = "simctl runtime list" ]; then
          printf '{'; first=1
          for f in "$DIR"/images/*.json; do
            [ -e "$f" ] || continue
            [ "$first" = 1 ] || printf ','
            cat "$f"; first=0
          done
          printf '}\\n'; exit 0
        fi
        if [ "$1 $2 $3" = "simctl runtime delete" ]; then
          dry=0
          for a in "$@"; do [ "$a" = "--dry-run" ] && dry=1; done
          [ -f "$DIR/targets.txt" ] || exit 0
          while read -r id; do
            [ -n "$id" ] || continue
            [ -e "$DIR/images/$id.json" ] || continue
            if [ "$dry" = 1 ]; then
              echo "Would delete P: $id iOS (Ready)"
            else
              name="$(cat "$DIR/cache-$id.txt" 2>/dev/null)"
              rm -f "$DIR/images/$id.json"
              [ -n "$name" ] && rm -rf "$DIR"/dyld/*/"$name"
            fi
          done < "$DIR/targets.txt"
          exit 0
        fi
        if [ "$1 $2" = "simctl list" ]; then cat "$DIR/list.json"; exit 0; fi
        exit 1
        """

    init(base: String) throws {
        root = base + "/fake-simctl"
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/images", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: root + "/dyld/25F84", withIntermediateDirectories: true)
        try Self.script.write(toFile: executable, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable)
        try """
        {"runtimes": [
          {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "buildversion": "23B86"},
          {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-1", "buildversion": "23B5059e"}
        ], "devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-1": [{}, {}]}}
        """.write(toFile: root + "/list.json", atomically: true, encoding: .utf8)
    }

    /// 本体を 1 つ置く。`cacheMegabytes` ぶんの共有キャッシュも作る。
    func addImage(id: String, build: String, sizeBytes: Int64, cacheMegabytes: Int, target: Bool) throws {
        let runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-1"
        try """
        "\(id)": {"identifier": "\(id)", "runtimeIdentifier": "\(runtime)", "version": "26.1",
          "build": "\(build)", "sizeBytes": \(sizeBytes), "lastUsedAt": "2025-10-27T09:37:24Z"}
        """.write(toFile: root + "/images/\(id).json", atomically: true, encoding: .utf8)
        let cacheName = runtime + "." + build
        try cacheName.write(toFile: root + "/cache-\(id).txt", atomically: true, encoding: .utf8)
        let cacheDir = dyldRoot + "/25F84/" + cacheName
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: cacheMegabytes * 1024 * 1024)
            .write(to: URL(fileURLWithPath: cacheDir + "/cache.bin"))
        if target {
            let path = root + "/targets.txt"
            let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try (existing + id + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func imageExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: root + "/images/\(id).json")
    }
}

@Suite("シミュレータ本体を simctl 経由で片づける")
struct SimulatorRuntimeRuleTests {
    private let betaId = "70224A2C-559D-4C8B-83A3-DD2B8060185C"
    private let releaseId = "00E5C5F8-59D9-4AE7-9DB5-3B691935C812"

    private func writeRule(_ sandbox: Sandbox, fake: FakeSimctl, measureArguments: [String]) throws {
        let rule: [String: Any] = [
            "id": "fake-runtimes", "title": "fake runtimes", "tier": "A", "kind": "command",
            "command": [
                "executable": fake.executable, "arguments": ["simctl", "runtime", "delete", "--outdated"],
            ],
            "measure": [
                "kind": "simctlRuntimes",
                "command": ["executable": fake.executable, "arguments": measureArguments],
                "paths": [fake.dyldRoot],
            ],
            "whatIsLost": "old runtime",
        ]
        try JSONSerialization.data(withJSONObject: [rule])
            .write(to: URL(fileURLWithPath: sandbox.env.rulesOverrideDir + "/00-fake-runtimes.json"))
    }

    @Test("見積もりは本体の量と共有キャッシュの合計で、何が消えるかを 1 件ずつ出す")
    func scanShowsImageAndCache() async throws {
        let sandbox = try Sandbox()
        let fake = try FakeSimctl(base: sandbox.home)
        try fake.addImage(id: betaId, build: "23B5059e", sizeBytes: 5_000_000, cacheMegabytes: 2, target: true)
        try fake.addImage(id: releaseId, build: "23B86", sizeBytes: 9_000_000, cacheMegabytes: 3, target: false)
        try writeRule(
            sandbox, fake: fake, measureArguments: ["simctl", "runtime", "delete", "--outdated", "--dry-run"])

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["fake-runtimes"], useCache: false)
        let item = try #require(result.items.first { $0.ruleId == "fake-runtimes" })
        let cache = DirectoryMeter.measure(
            path: fake.dyldRoot + "/25F84/com.apple.CoreSimulator.SimRuntime.iOS-26-1.23B5059e"
        ).bytes

        #expect(item.state == .ready)
        #expect(item.sizeKnown)
        #expect(item.bytes == 5_000_000 + cache, "消えない本体（23B86）を数えない")
        #expect(!item.undoable)
        #expect(item.details.count == 1)
        #expect(item.details.first?.contains("23B5059e") == true)
        #expect(fake.imageExists(betaId), "スキャンでは消さない")
    }

    @Test("実行すると本体が消え、前後の差を空けた量として報告する")
    func applyReportsReclaimed() async throws {
        let sandbox = try Sandbox()
        let fake = try FakeSimctl(base: sandbox.home)
        try fake.addImage(id: betaId, build: "23B5059e", sizeBytes: 5_000_000, cacheMegabytes: 2, target: true)
        try fake.addImage(id: releaseId, build: "23B86", sizeBytes: 9_000_000, cacheMegabytes: 3, target: false)
        try writeRule(
            sandbox, fake: fake, measureArguments: ["simctl", "runtime", "delete", "--outdated", "--dry-run"])
        let catalog = sandbox.catalog()

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: catalog, ruleIds: ["fake-runtimes"], useCache: false)
        let shown = try #require(result.items.first { $0.ruleId == "fake-runtimes" }).bytes
        let plan = try Planner().plan(from: result, tiers: [.a], select: [], deselect: [])
        let outcome = try Executor(
            env: sandbox.env, config: sandbox.config, audit: AuditLog(dir: sandbox.env.auditDir), catalogVersion: 0
        )
        .apply(plan: plan, catalog: catalog, dryRun: false)

        #expect(outcome.failed.isEmpty)
        #expect(!fake.imageExists(betaId))
        #expect(fake.imageExists(releaseId), "新しいビルドは残る")
        let command = try #require(outcome.commandsRun.first { $0.ruleId == "fake-runtimes" })
        #expect(command.reclaimedBytes == shown, "見せた量と実際に空いた量が一致する")
    }

    @Test("dry-run でない測り方は実行せず、量は「不明」にする")
    func measureWithoutDryRunIsRefused() async throws {
        let sandbox = try Sandbox()
        let fake = try FakeSimctl(base: sandbox.home)
        try fake.addImage(id: betaId, build: "23B5059e", sizeBytes: 5_000_000, cacheMegabytes: 1, target: true)
        // 書き間違えて --dry-run を落とした測り方
        try writeRule(sandbox, fake: fake, measureArguments: ["simctl", "runtime", "delete", "--outdated"])

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["fake-runtimes"], useCache: false)
        let item = try #require(result.items.first { $0.ruleId == "fake-runtimes" })

        #expect(!item.sizeKnown)
        #expect(fake.imageExists(betaId), "測るつもりで消してしまわない")
    }

    @Test("対象が無ければ実行せずに外す")
    func nothingToDeleteIsSkipped() async throws {
        let sandbox = try Sandbox()
        let fake = try FakeSimctl(base: sandbox.home)
        try fake.addImage(id: releaseId, build: "23B86", sizeBytes: 9_000_000, cacheMegabytes: 1, target: false)
        try writeRule(
            sandbox, fake: fake, measureArguments: ["simctl", "runtime", "delete", "--outdated", "--dry-run"])

        let result = await Scanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), ruleIds: ["fake-runtimes"], useCache: false)
        let item = try #require(result.items.first { $0.ruleId == "fake-runtimes" })
        #expect(item.state == .skipped)
        #expect(item.reason == "empty")
    }

    @Test("同梱ルールに 3 本が入り、階層が決めたとおりになっている")
    func bundledRulesExist() throws {
        let sandbox = try Sandbox()
        let catalog = sandbox.catalog()
        #expect(catalog.rule(id: "simulator-runtimes-outdated")?.tier == .a)
        #expect(catalog.rule(id: "simulator-runtimes-unused")?.tier == .b)
        #expect(catalog.rule(id: "xctest-device-clones")?.tier == .b)
        for id in ["simulator-runtimes-outdated", "simulator-runtimes-unused"] {
            let rule = try #require(catalog.rule(id: id))
            let measure = try #require(rule.measure?.command)
            #expect(measure.arguments.contains("--dry-run"), "\(id) の測り方は dry-run でなければならない")
            #expect(rule.command?.arguments.contains("--dry-run") == false)
        }
    }

    @Test("測っている場所（XCTestDevices）は「まだ見ていない場所」に出さない")
    func measuredPlacesCountAsCovered() async throws {
        let sandbox = try Sandbox()
        let clones = sandbox.home + "/Library/Developer/XCTestDevices/CLONE-1"
        try FileManager.default.createDirectory(atPath: clones, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 6 * 1024 * 1024).write(to: URL(fileURLWithPath: clones + "/data.bin"))

        let result = await UncoveredScanner(env: sandbox.env, config: sandbox.config)
            .scan(catalog: sandbox.catalog(), minimumBytes: 1024 * 1024)
        #expect(!result.places.contains { $0.path.contains("/XCTestDevices") })
    }
}
