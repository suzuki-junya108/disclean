import CryptoKit
import Foundation
import Testing
@testable import DiscleanKit

@Suite("CatalogUpdate: 署名・版数・期限の検証")
struct CatalogUpdateVerifierTests {
    private func makeManifest(
        catalogVersion: Int = 1, publishedAt: Date = Date(), expiresIn: TimeInterval = 90 * 86_400,
        minDiscleanVersion: String = "0.1.0", keyId: String = "test-key", schemaVersion: Int = 1
    ) -> [String: Any] {
        [
            "schemaVersion": schemaVersion,
            "catalogVersion": catalogVersion,
            "publishedAt": JSONIO.string(from: publishedAt),
            "expiresAt": JSONIO.string(from: publishedAt.addingTimeInterval(expiresIn)),
            "minDiscleanVersion": minDiscleanVersion,
            "keyId": keyId,
            "archive": ["name": "catalog-1.tar.gz", "sha256": String(repeating: "0", count: 64), "bytes": 10],
            "files": [],
            "revocations": [],
        ]
    }

    private func sign(_ object: [String: Any], key: Curve25519.Signing.PrivateKey) throws -> (Data, String) {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let signature = try key.signature(for: data)
        return (data, signature.base64EncodedString())
    }

    private func verifier(_ key: Curve25519.Signing.PrivateKey, keyId: String = "test-key") -> ManifestVerifier {
        ManifestVerifier(trustedKeys: [
            ReleaseKey(keyId: keyId, publicKey: key.publicKey.rawRepresentation.base64EncodedString(), validFrom: nil)
        ])
    }

    @Test("正しく署名された manifest は受け入れる")
    func validSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let (data, signature) = try sign(makeManifest(), key: key)
        let result = verifier(key).verifyManifest(data: data, signatureBase64: signature)
        #expect(try result.get().catalogVersion == 1)
    }

    @Test("署名を 1 バイト改竄したら拒否する")
    func tamperedSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let (data, signature) = try sign(makeManifest(), key: key)
        var raw = try #require(Data(base64Encoded: signature))
        raw[0] ^= 0x01
        let result = verifier(key).verifyManifest(data: data, signatureBase64: raw.base64EncodedString())
        #expect(result == .failure(.signature))
    }

    @Test("本文を改竄したら拒否する")
    func tamperedBody() throws {
        let key = Curve25519.Signing.PrivateKey()
        let (data, signature) = try sign(makeManifest(), key: key)
        var mutated = data
        mutated.append(0x20)
        let result = verifier(key).verifyManifest(data: mutated, signatureBase64: signature)
        #expect(result == .failure(.schema) || result == .failure(.signature))
    }

    @Test("知らない鍵で署名されていたら拒否する")
    func unknownKey() throws {
        let attacker = Curve25519.Signing.PrivateKey()
        let publisher = Curve25519.Signing.PrivateKey()
        let (data, signature) = try sign(makeManifest(keyId: "other-key"), key: attacker)
        let result = verifier(publisher).verifyManifest(data: data, signatureBase64: signature)
        #expect(result == .failure(.unknownKey))
    }

    @Test("巻き戻し（古い版数）は拒否する")
    func rollback() {
        var state = UpdateState()
        state.appliedCatalogVersion = 5
        let manifest = decoded(makeManifest(catalogVersion: 4))
        #expect(ManifestVerifier(trustedKeys: []).accept(manifest: manifest, state: state) == .rollbackDetected)
    }

    @Test("発行日時の逆行も拒否する")
    func publishedAtRegression() {
        var state = UpdateState()
        state.appliedCatalogVersion = 1
        state.appliedPublishedAt = Date()
        let manifest = decoded(makeManifest(catalogVersion: 2, publishedAt: Date().addingTimeInterval(-86_400)))
        #expect(ManifestVerifier(trustedKeys: []).accept(manifest: manifest, state: state) == .rollbackDetected)
    }

    @Test("期限切れ manifest は拒否する（差し止め攻撃の検知）")
    func expired() {
        let manifest = decoded(
            makeManifest(catalogVersion: 2, publishedAt: Date().addingTimeInterval(-200 * 86_400)))
        #expect(ManifestVerifier(trustedKeys: []).accept(manifest: manifest, state: UpdateState()) == .expired)
    }

    @Test("本体が古すぎる場合は適用しない")
    func appTooOld() {
        let manifest = decoded(makeManifest(catalogVersion: 2, minDiscleanVersion: "9.0.0"))
        #expect(ManifestVerifier(trustedKeys: []).accept(manifest: manifest, state: UpdateState()) == .appVersionTooOld)
    }

    @Test("未知のスキーマ版数は拒否する")
    func schemaMismatch() {
        let manifest = decoded(makeManifest(catalogVersion: 2, schemaVersion: 2))
        #expect(ManifestVerifier(trustedKeys: []).accept(manifest: manifest, state: UpdateState()) == .schema)
    }

    @Test("ハッシュとサイズの不一致を検出する")
    func hashMismatch() {
        let verifier = ManifestVerifier(trustedKeys: [])
        let data = Data("hello".utf8)
        let correct = ManifestFile(
            name: "a.json", sha256: ManifestVerifier.sha256Hex(data), bytes: Int64(data.count))
        #expect(verifier.verifyFile(data: data, expected: correct) == nil)
        let wrongHash = ManifestFile(
            name: "a.json", sha256: String(repeating: "a", count: 64),
            bytes: Int64(data.count))
        #expect(verifier.verifyFile(data: data, expected: wrongHash) == .hashMismatch)
        let wrongSize = ManifestFile(name: "a.json", sha256: correct.sha256, bytes: 999)
        #expect(verifier.verifyFile(data: data, expected: wrongSize) == .hashMismatch)
    }

    @Test("同一版数は「更新なし」として扱える")
    func sameVersion() {
        var state = UpdateState()
        state.appliedCatalogVersion = 3
        let manifest = decoded(makeManifest(catalogVersion: 3))
        #expect(ManifestVerifier(trustedKeys: []).accept(manifest: manifest, state: state) == .rollbackDetected)
        #expect(manifest.catalogVersion == state.appliedCatalogVersion)
    }

    private func decoded(_ object: [String: Any]) -> CatalogManifest {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
            let manifest = try? JSONIO.decoder().decode(CatalogManifest.self, from: data)
        else {
            fatalError("test fixture is not a valid manifest")
        }
        return manifest
    }
}

@Suite("CatalogUpdate: 差分の分類")
struct CatalogUpdateDiffTests {
    private func rule(
        id: String, tier: Tier = .a, paths: [String] = ["~/Library/Caches/x"], minAgeDays: Int? = nil,
        command: CommandSpec? = nil, title: String = "t", minMacOS: String? = nil, enabled: Bool = true
    ) -> Rule {
        Rule(
            id: id, title: title, tier: tier, kind: command == nil ? .directory : .command,
            paths: command == nil ? paths : nil, command: command, minAgeDays: minAgeDays,
            whatIsLost: "w", enabled: enabled, minMacOS: minMacOS)
    }

    @Test("ルール追加は拡大（承認必須）")
    func ruleAdded() {
        let diff = CatalogDiffer.diff(current: [], next: [rule(id: "new-rule")])
        #expect(diff.requiresApproval)
        #expect(diff.expanding.first?.change == .ruleAdded)
        #expect(diff.newPaths == ["~/Library/Caches/x"])
    }

    @Test("パス追加は拡大、パス削除は縮小")
    func paths() {
        let before = [rule(id: "r", paths: ["~/Library/Caches/a"])]
        let after = [rule(id: "r", paths: ["~/Library/Caches/a", "~/Library/Caches/b"])]
        #expect(CatalogDiffer.diff(current: before, next: after).expanding.first?.change == .pathAdded)
        #expect(CatalogDiffer.diff(current: after, next: before).shrinking.first?.change == .pathRemoved)
        #expect(!CatalogDiffer.diff(current: after, next: before).requiresApproval)
    }

    @Test("Tier 引き上げは拡大、引き下げは縮小")
    func tiers() {
        let b = [rule(id: "r", tier: .b)]
        let a = [rule(id: "r", tier: .a)]
        #expect(CatalogDiffer.diff(current: b, next: a).expanding.first?.change == .tierRaised)
        #expect(CatalogDiffer.diff(current: a, next: b).shrinking.first?.change == .tierLowered)
    }

    @Test("コマンド変更は拡大")
    func commandChanged() {
        let before = [rule(id: "r", command: CommandSpec(executable: "npm", arguments: ["cache", "clean"]))]
        let after = [rule(id: "r", command: CommandSpec(executable: "rm", arguments: ["-rf", "/"]))]
        #expect(CatalogDiffer.diff(current: before, next: after).expanding.first?.change == .commandChanged)
    }

    @Test("最小日数の短縮は拡大、延長は縮小")
    func minAge() {
        let strict = [rule(id: "r", minAgeDays: 7)]
        let loose = [rule(id: "r", minAgeDays: 1)]
        #expect(CatalogDiffer.diff(current: strict, next: loose).expanding.first?.change == .ageRelaxed)
        #expect(CatalogDiffer.diff(current: loose, next: strict).shrinking.first?.change == .ageTightened)
    }

    @Test("OS 範囲の拡大は拡大、縮小は縮小")
    func osScope() {
        let narrow = [rule(id: "r", minMacOS: "26.0")]
        let wide = [rule(id: "r", minMacOS: "14.0")]
        #expect(CatalogDiffer.diff(current: narrow, next: wide).expanding.first?.change == .osScopeWidened)
        #expect(CatalogDiffer.diff(current: wide, next: narrow).shrinking.first?.change == .osScopeNarrowed)
    }

    @Test("文言だけの変更は中立（承認不要）")
    func textOnly() {
        let before = [rule(id: "r", title: "old")]
        let after = [rule(id: "r", title: "new")]
        let diff = CatalogDiffer.diff(current: before, next: after)
        #expect(diff.neutral.first?.change == .textChanged)
        #expect(!diff.requiresApproval)
    }

    @Test("ルール削除と revocation は縮小")
    func removals() {
        let before = [rule(id: "r")]
        #expect(CatalogDiffer.diff(current: before, next: []).shrinking.first?.change == .ruleRemoved)
        let revoked = CatalogDiffer.diff(current: before, next: before, revocations: ["r"])
        #expect(revoked.shrinking.contains { $0.change == .revoked })
        #expect(!revoked.requiresApproval)
    }

    @Test("有効化は拡大、無効化は縮小")
    func enabling() {
        let off = [rule(id: "r", enabled: false)]
        let on = [rule(id: "r", enabled: true)]
        #expect(CatalogDiffer.diff(current: off, next: on).expanding.contains { $0.change == .ruleAdded })
        #expect(CatalogDiffer.diff(current: on, next: off).shrinking.contains { $0.change == .ruleRemoved })
    }
}
