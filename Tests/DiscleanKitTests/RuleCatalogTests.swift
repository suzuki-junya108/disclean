import Foundation
import Testing
@testable import DiscleanKit

@Suite("RuleCatalog の検証と上書き")
struct RuleCatalogTests {
    private func loader(_ tmp: TempHome) -> RuleCatalogLoader {
        RuleCatalogLoader(env: tmp.env, config: Config(excludedPaths: []))
    }

    private func rule(
        id: String = "test-rule", tier: Tier = .a, kind: RuleKind = .directory,
        paths: [String]? = ["~/Library/Caches/test"], command: CommandSpec? = nil,
        manualSteps: String? = nil, timeoutSeconds: Int = 180,
        minMacOS: String? = nil, maxMacOS: String? = nil
    ) -> Rule {
        Rule(
            id: id, title: "t", tier: tier, kind: kind, paths: paths, command: command,
            whatIsLost: "w", manualSteps: manualSteps, timeoutSeconds: timeoutSeconds,
            minMacOS: minMacOS, maxMacOS: maxMacOS)
    }

    @Test("同梱カタログは全件が検証を通る")
    func builtinIsValid() throws {
        let tmp = try TempHome()
        let catalog = loader(tmp).load()
        #expect(catalog.errors.isEmpty)
        #expect(catalog.entries.count >= 20)
        #expect(catalog.entries.allSatisfy { $0.source == .builtin })
    }

    @Test("禁止パスを含むユーザールールは拒否する")
    func forbiddenPath() throws {
        let tmp = try TempHome()
        let dir = tmp.home + "/config/rules.d"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let json = """
            [{"id":"evil","title":"evil","tier":"A","kind":"directory","paths":["/"],"whatIsLost":"everything"}]
            """
        try json.write(toFile: dir + "/99-bad.json", atomically: true, encoding: .utf8)
        let catalog = loader(tmp).load()
        #expect(catalog.rule(id: "evil") == nil)
        #expect(catalog.errors.contains { $0.reason.contains("forbidden path") })
    }

    @Test("ユーザールールは同一 id の同梱ルールを置換する")
    func userOverridesBuiltin() throws {
        let tmp = try TempHome()
        let dir = tmp.home + "/config/rules.d"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let json = """
            [{"id":"npm-cache","title":"mine","tier":"B","kind":"directory",
              "paths":["~/Library/Caches/mine"],"whatIsLost":"nothing"}]
            """
        try json.write(toFile: dir + "/00-mine.json", atomically: true, encoding: .utf8)
        let catalog = loader(tmp).load()
        #expect(catalog.rule(id: "npm-cache")?.title == "mine")
        #expect(catalog.source(of: "npm-cache") == .user)
    }

    @Test("壊れた JSON はそのファイルだけ拒否し、他は生きる")
    func brokenJSON() throws {
        let tmp = try TempHome()
        let dir = tmp.home + "/config/rules.d"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "{ not json".write(toFile: dir + "/50-broken.json", atomically: true, encoding: .utf8)
        let catalog = loader(tmp).load()
        #expect(!catalog.errors.isEmpty)
        #expect(catalog.rule(id: "npm-cache") != nil)
    }

    @Test("同一ファイル内の重複 id は拒否する")
    func duplicateId() throws {
        let tmp = try TempHome()
        let dir = tmp.home + "/config/rules.d"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let json = """
            [{"id":"dup","title":"a","tier":"A","kind":"directory","paths":["~/Library/Caches/a"],"whatIsLost":"x"},
             {"id":"dup","title":"b","tier":"A","kind":"directory","paths":["~/Library/Caches/b"],"whatIsLost":"x"}]
            """
        try json.write(toFile: dir + "/60-dup.json", atomically: true, encoding: .utf8)
        let catalog = loader(tmp).load()
        #expect(catalog.errors.contains { $0.reason == "duplicate id" })
    }

    @Test("スキーマ違反の各経路を拒否する")
    func schemaViolations() throws {
        let tmp = try TempHome()
        let load = loader(tmp)
        #expect(load.validate(rule(id: "Bad_Id")) != nil)
        #expect(load.validate(rule(id: "")) != nil)
        #expect(load.validate(rule(timeoutSeconds: 0)) != nil)
        #expect(load.validate(rule(timeoutSeconds: 1000)) != nil)
        #expect(load.validate(rule(tier: .c, kind: .directory)) != nil)
        #expect(load.validate(rule(tier: .c, kind: .report, manualSteps: nil)) != nil)
        #expect(load.validate(rule(kind: .directory, paths: [])) != nil)
        #expect(load.validate(rule(kind: .command, paths: nil, command: nil)) != nil)
        #expect(load.validate(rule(kind: .report, paths: nil)) != nil)
        #expect(load.validate(rule(tier: .c, kind: .report, manualSteps: "手順")) == nil)
        #expect(
            load.validate(
                rule(kind: .command, paths: nil, command: CommandSpec(executable: "npm"))) == nil)
    }

    @Test("OS 条件の範囲外は無効化される")
    func osScope() throws {
        let tmp = try TempHome()
        let load = loader(tmp)
        #expect(load.osIneligibility(rule(minMacOS: "99.0")) == "os-unsupported")
        #expect(load.osIneligibility(rule(maxMacOS: "1.0")) == "os-unsupported")
        #expect(load.osIneligibility(rule(minMacOS: "14.0")) == nil)
        #expect(load.osIneligibility(rule(minMacOS: "not-a-version")) == "invalid-minMacOS")
        #expect(load.osIneligibility(rule(maxMacOS: "x")) == "invalid-maxMacOS")
    }

    @Test("revocation はカタログから外れる")
    func revocation() throws {
        let tmp = try TempHome()
        let catalog = loader(tmp).load(revocations: ["npm-cache"])
        #expect(catalog.rule(id: "npm-cache") == nil)
        #expect(catalog.disabledByOS.contains { $0.ruleId == "npm-cache" && $0.reason == "revoked" })
    }

    @Test("バージョン比較")
    func semanticVersion() throws {
        let old = try #require(SemanticVersion("14.0"))
        let new = try #require(SemanticVersion("26.5.2"))
        #expect(old < new)
        #expect(try #require(SemanticVersion("1.2")) == #require(SemanticVersion("1.2.0")))
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("abc") == nil)
        #expect(try #require(SemanticVersion("2.10")) > #require(SemanticVersion("2.9")))
    }
}

@Suite("スキップ理由の表示")
struct SkipReasonTests {
    @Test(
        "理由コードを日本語にする",
        arguments: [
            ("too-recent", "新しすぎます"),
            ("empty", "空でした"),
            ("cross-volume", "別のディスクにあります"),
            ("destination-exists", "戻す先に同じ名前があります"),
        ])
    func japanese(code: String, expected: String) {
        #expect(SkipReason.describe(code, japanese: true) == expected)
    }

    @Test("アプリ名つきの理由も読める形にする")
    func appRunning() {
        let text = SkipReason.describe("app-running:com.apple.dt.Xcode", japanese: true)
        #expect(text.contains("アプリが起動中"))
        #expect(text.contains("com.apple.dt.Xcode"))
    }

    @Test("知らない理由コードはそのまま返す")
    func unknown() {
        #expect(SkipReason.describe("brand-new-reason", japanese: true) == "brand-new-reason")
    }
}
