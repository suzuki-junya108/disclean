import Foundation
import CryptoKit

/// 信頼する公開鍵 1 件。
public struct ReleaseKey: Codable, Sendable, Equatable {
    public let keyId: String
    /// base64 の Ed25519 公開鍵（32 バイト）。
    public let publicKey: String
    public let validFrom: Date?
}

/// 更新物の拒否理由。すべて exit 7 に対応する。
public enum VerificationFailure: String, Error, Sendable, Equatable {
    case signature
    case unknownKey = "unknown-key"
    case hashMismatch = "hash-mismatch"
    case rollbackDetected = "rollback-detected"
    case expired
    case schema
    case appVersionTooOld = "app-version-too-old"
}

/// 署名・ハッシュ・版数・期限の検証。ネットワークには触れない。
public struct ManifestVerifier: Sendable {
    public let trustedKeys: [ReleaseKey]

    public init(trustedKeys: [ReleaseKey]) {
        self.trustedKeys = trustedKeys
    }

    /// 埋め込みの公開鍵を読む。debug ビルドに限り、環境変数でテスト鍵を追加できる。
    public static func withEmbeddedKeys(env: [String: String] = ProcessInfo.processInfo.environment) -> ManifestVerifier
    {
        var keys: [ReleaseKey] = []
        if let url = Bundle.module.url(forResource: "release-keys", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONIO.decoder().decode([ReleaseKey].self, from: data)
        {
            keys = decoded
        }
        #if DEBUG
            // テスト用の信頼鍵注入は debug ビルドでのみ有効（release では値を無視する）。
            if let path = env["DISCLEAN_UPDATE_TRUSTED_KEYS_FILE"],
                let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                let decoded = try? JSONIO.decoder().decode([ReleaseKey].self, from: data)
            {
                keys.append(contentsOf: decoded)
            }
        #endif
        return ManifestVerifier(trustedKeys: keys)
    }

    /// manifest の署名を検証し、デコード済みの値を返す。
    public func verifyManifest(data: Data, signatureBase64: String) -> Result<CatalogManifest, VerificationFailure> {
        guard let manifest = try? JSONIO.decoder().decode(CatalogManifest.self, from: data) else {
            return .failure(.schema)
        }
        guard let key = trustedKeys.first(where: { $0.keyId == manifest.keyId }) else {
            return .failure(.unknownKey)
        }
        guard let keyData = Data(base64Encoded: key.publicKey),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
            let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return .failure(.signature)
        }
        guard publicKey.isValidSignature(signature, for: data) else {
            return .failure(.signature)
        }
        return .success(manifest)
    }

    /// 版数・期限・本体バージョンの整合を確かめる。
    public func accept(
        manifest: CatalogManifest, state: UpdateState, now: Date = Date(),
        appVersion: String = DiscleanVersion.current
    ) -> VerificationFailure? {
        if manifest.schemaVersion != 1 { return .schema }
        if manifest.catalogVersion <= state.appliedCatalogVersion { return .rollbackDetected }
        if let appliedPublishedAt = state.appliedPublishedAt, manifest.publishedAt < appliedPublishedAt {
            return .rollbackDetected
        }
        if manifest.expiresAt <= now { return .expired }
        guard let required = SemanticVersion(manifest.minDiscleanVersion),
            let current = SemanticVersion(appVersion)
        else { return .schema }
        if current < required { return .appVersionTooOld }
        return nil
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public func verifyFile(data: Data, expected: ManifestFile) -> VerificationFailure? {
        guard Int64(data.count) == expected.bytes else { return .hashMismatch }
        guard ManifestVerifier.sha256Hex(data).lowercased() == expected.sha256.lowercased() else {
            return .hashMismatch
        }
        return nil
    }
}
