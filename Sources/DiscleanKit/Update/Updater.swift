import Foundation

/// 更新チェック 1 回分の結果。
public struct UpdateCheckOutcome: Sendable {
    public var appliedVersion: Int
    public var availableVersion: Int?
    public var publishedAt: Date?
    public var expiresAt: Date?
    public var diff: CatalogDiff
    public var autoApplied: Bool
    public var failure: VerificationFailure?
    public var networkError: String?
    public var appVersion: String?
    public var appMinMacOS: String?
    public var installMethod: InstallMethod
    public var warnings: [String]

    public var requiresApproval: Bool { diff.requiresApproval && !autoApplied }
}

/// 更新の取得・検証・差分分類・適用。`URLSession` を使うのはこの型だけ。
public struct Updater: Sendable {
    private let env: DiscleanEnvironment
    private let config: Config
    private let store: CatalogStore
    private let verifier: ManifestVerifier
    private let audit: AuditLog

    /// リダイレクトを許すホスト（これ以外へ飛んだら中止する）。
    static let allowedHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com", "127.0.0.1", "localhost",
    ]

    public init(env: DiscleanEnvironment, config: Config, audit: AuditLog) {
        self.env = env
        self.config = config
        self.store = CatalogStore(env: env)
        self.verifier = ManifestVerifier.withEmbeddedKeys()
        self.audit = audit
    }

    /// 前回チェックからの経過が間隔を超えているか。
    public func isDue(state: UpdateState, now: Date = Date()) -> Bool {
        guard config.autoUpdate else { return false }
        guard let last = state.lastCheckedAt else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(config.updateIntervalHours) * 3600
    }

    /// 取得 → 検証 → staged → 差分分類 → （縮小・中立のみなら）自動適用。
    public func check(
        state: inout UpdateState, now: Date = Date(), timeout: TimeInterval = 20
    ) async -> UpdateCheckOutcome {
        var outcome = UpdateCheckOutcome(
            appliedVersion: state.appliedCatalogVersion, availableVersion: nil, publishedAt: nil,
            expiresAt: nil, diff: CatalogDiff(), autoApplied: false, failure: nil, networkError: nil,
            appVersion: nil, appMinMacOS: nil, installMethod: Updater.detectInstallMethod(), warnings: [])
        state.installMethod = outcome.installMethod
        state.lastCheckedAt = now

        let base = config.updateEndpoint
        do {
            let manifestData = try await fetch(base + "catalog-manifest.json", timeout: timeout)
            let signature = try await fetch(base + "catalog-manifest.json.sig", timeout: timeout)
            let signatureText = String(bytes: signature, encoding: .utf8) ?? ""

            switch verifier.verifyManifest(data: manifestData, signatureBase64: signatureText) {
            case .failure(let failure):
                outcome.failure = failure
                state.lastCheckResult = .rejected
                state.lastFailureReason = failure.rawValue
                logRejection(failure, now: now, state: state)
                return outcome
            case .success(let manifest):
                outcome.availableVersion = manifest.catalogVersion
                outcome.publishedAt = manifest.publishedAt
                outcome.expiresAt = manifest.expiresAt
                outcome.appVersion = manifest.latestApp?.version
                outcome.appMinMacOS = manifest.latestApp?.minMacOS
                state.availableAppVersion = manifest.latestApp?.version

                if let failure = verifier.accept(manifest: manifest, state: state, now: now) {
                    if failure == .rollbackDetected && manifest.catalogVersion == state.appliedCatalogVersion {
                        // 同一版数なら「更新なし」であって攻撃ではない。
                        state.lastCheckResult = .noUpdate
                        applyRevocations(manifest.revocations, state: &state)
                        return outcome
                    }
                    outcome.failure = failure
                    state.lastCheckResult = failure == .expired ? .rejected : .rejected
                    state.lastFailureReason = failure.rawValue
                    if failure == .expired {
                        outcome.warnings.append(
                            "catalog manifest expired at \(JSONIO.string(from: manifest.expiresAt))")
                    }
                    logRejection(failure, now: now, state: state)
                    return outcome
                }

                return try await download(
                    manifest: manifest, source: FetchSource(base: base, timeout: timeout),
                    outcome: outcome, state: &state, now: now)
            }
        } catch {
            outcome.networkError = "\(error)"
            state.lastCheckResult = .networkError
            return outcome
        }
    }

    /// 検証を通った manifest に基づいてカタログ本体を取得し、staged に置いて差分を分類する。
    /// 縮小・中立だけならその場で適用し、拡大が含まれていれば承認待ちにする。
    private func download(
        manifest: CatalogManifest, source: FetchSource,
        outcome: UpdateCheckOutcome, state: inout UpdateState, now: Date
    ) async throws -> UpdateCheckOutcome {
        let base = source.base
        let timeout = source.timeout
        var outcome = outcome
        let archive = try await fetch(base + manifest.archive.name, timeout: timeout)
        if let failure = verifier.verifyFile(data: archive, expected: manifest.archive) {
            return reject(failure, outcome: outcome, state: &state, now: now)
        }
        let files = try extract(archive: archive, manifest: manifest)
        for expected in manifest.files {
            guard let data = files[expected.name] else {
                return reject(.hashMismatch, outcome: outcome, state: &state, now: now)
            }
            if let failure = verifier.verifyFile(data: data, expected: expected) {
                return reject(failure, outcome: outcome, state: &state, now: now)
            }
        }

        try store.stage(manifest: manifest, ruleFiles: files)
        state.stagedCatalogVersion = manifest.catalogVersion

        outcome.diff = CatalogDiffer.diff(
            current: currentEffectiveRules(),
            next: store.stagedRules(version: manifest.catalogVersion),
            revocations: manifest.revocations)
        applyRevocations(manifest.revocations, state: &state)

        if outcome.diff.requiresApproval {
            state.lastCheckResult = .pendingApproval
            state.lastFailureReason = nil
        } else {
            try apply(version: manifest.catalogVersion, manifest: manifest, state: &state, now: now)
            outcome.autoApplied = true
            outcome.appliedVersion = manifest.catalogVersion
            state.lastCheckResult = .ok
        }
        return outcome
    }

    /// 受け取ったものを適用せずに拒否する（状態と監査ログを必ず残す）。
    private func reject(
        _ failure: VerificationFailure, outcome: UpdateCheckOutcome, state: inout UpdateState, now: Date
    ) -> UpdateCheckOutcome {
        var outcome = outcome
        outcome.failure = failure
        state.lastCheckResult = .rejected
        state.lastFailureReason = failure.rawValue
        logRejection(failure, now: now, state: state)
        return outcome
    }

    /// staged を有効化する（承認後、または縮小のみの自動適用）。
    public func apply(version: Int, manifest: CatalogManifest?, state: inout UpdateState, now: Date = Date()) throws {
        try store.promote(version: version)
        state.appliedCatalogVersion = version
        state.appliedAt = now
        state.appliedPublishedAt = manifest?.publishedAt ?? store.activeManifest()?.publishedAt
        state.stagedCatalogVersion = nil
        store.discardStaged(olderThanOrEqual: version)
        try? audit.append(
            AuditRecord(
                ts: now, action: .catalogUpdate, runId: "-", ruleId: "-", bytes: 0, result: .ok,
                reason: "applied catalog \(version)", env: env, catalogVersion: version))
    }

    public func rollback(state: inout UpdateState, now: Date = Date()) throws -> Int? {
        guard let version = try store.rollback() else { return nil }
        state.appliedCatalogVersion = version
        state.appliedAt = now
        try? audit.append(
            AuditRecord(
                ts: now, action: .catalogUpdate, runId: "-", ruleId: "-", bytes: 0, result: .ok,
                reason: "rolled back to catalog \(version)", env: env, catalogVersion: version))
        return version
    }

    /// revocation は削除対象が減る方向のため、承認を待たずに反映する。
    private func applyRevocations(_ revocations: [String], state: inout UpdateState) {
        guard state.revocations != revocations else { return }
        state.revocations = revocations
    }

    private func currentEffectiveRules() -> [Rule] {
        let active = store.activeRules()
        if !active.isEmpty { return active }
        let loader = RuleCatalogLoader(env: env, config: config)
        return loader.load().rules
    }

    private func logRejection(_ failure: VerificationFailure, now: Date, state: UpdateState) {
        try? audit.append(
            AuditRecord(
                ts: now, action: .catalogUpdate, runId: "-", ruleId: "-", bytes: 0, result: .failed,
                reason: failure.rawValue, env: env, catalogVersion: state.appliedCatalogVersion))
    }

    /// tar.gz をハッシュ検証済みの状態で展開し、`rules/*.json` を返す。
    private func extract(archive: Data, manifest: CatalogManifest) throws -> [String: Data] {
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory() + "disclean-update-" + UUID().uuidString
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(atPath: tmp) }
        let archivePath = tmp + "/catalog.tar.gz"
        try archive.write(to: URL(fileURLWithPath: archivePath))
        let result = CommandRunner.run(
            CommandSpec(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", archivePath, "-C", tmp, "--strip-components", "0"]),
            timeoutSeconds: 30)
        guard result.succeeded else { throw UpdaterError.extractionFailed(result.standardError) }

        var files: [String: Data] = [:]
        let rulesDir = tmp + "/rules"
        if let names = try? fm.contentsOfDirectory(atPath: rulesDir) {
            for name in names where name.hasSuffix(".json") {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: rulesDir + "/" + name)) {
                    files[name] = data
                }
            }
        }
        return files
    }

    /// HTTPS GET。許可ホスト以外へのリダイレクトは中止する。
    func fetch(_ urlString: String, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: urlString), let host = url.host else {
            throw UpdaterError.invalidURL(urlString)
        }
        guard url.scheme == "https" || Updater.allowedHosts.contains(host) else {
            throw UpdaterError.insecureScheme(urlString)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"
        request.setValue(Updater.userAgent(env: env), forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": Updater.userAgent(env: env)]
        let delegate = RedirectGuard()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdaterError.badResponse(-1) }
        guard (200..<300).contains(http.statusCode) else { throw UpdaterError.badResponse(http.statusCode) }
        return data
    }

    /// 送るのはバージョン情報だけ。識別子・パス・スキャン結果は含めない。
    static func userAgent(env: DiscleanEnvironment) -> String {
        "disclean/\(DiscleanVersion.current) (macOS \(env.osVersion); \(env.arch))"
    }

    /// 実行ファイルの位置から導入経路を判定する。
    public static func detectInstallMethod(executablePath: String = CommandLine.arguments.first ?? "") -> InstallMethod
    {
        let resolved = PathGuard.resolve(executablePath)
        if resolved.contains("/Cellar/") || resolved.contains("/homebrew/") { return .brew }
        if resolved.contains(".app/Contents/MacOS/") { return .app }
        return .manual
    }
}

/// 取得元と待ち時間の組。
struct FetchSource {
    let base: String
    let timeout: TimeInterval
}

public enum UpdaterError: Error, Equatable {
    case invalidURL(String)
    case insecureScheme(String)
    case badResponse(Int)
    case extractionFailed(String)
    case redirectNotAllowed(String)
}

/// リダイレクト先のホストを検査するデリゲート。
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let host = request.url?.host, Updater.allowedHosts.contains(host) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
