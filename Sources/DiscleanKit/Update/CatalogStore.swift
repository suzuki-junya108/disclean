import Foundation

/// 更新カタログの世代管理（staged / active / previous）。
/// `active` への切り替えはこの型の 1 経路のみで行う。
public struct CatalogStore: Sendable {
    private let env: DiscleanEnvironment

    public var activeDir: String { env.updatesDir + "/active" }
    public var previousDir: String { env.updatesDir + "/previous" }
    public var downloadsDir: String { env.updatesDir + "/downloads" }
    public func stagedDir(version: Int) -> String { env.updatesDir + "/staged/\(version)" }

    public init(env: DiscleanEnvironment) {
        self.env = env
    }

    public func activeManifest() -> CatalogManifest? {
        try? JSONIO.read(CatalogManifest.self, at: activeDir + "/manifest.json")
    }

    public func stagedManifest(version: Int) -> CatalogManifest? {
        try? JSONIO.read(CatalogManifest.self, at: stagedDir(version: version) + "/manifest.json")
    }

    /// 検証済みのカタログを staged に置く（この時点では有効化しない）。
    public func stage(manifest: CatalogManifest, ruleFiles: [String: Data]) throws {
        let dir = stagedDir(version: manifest.catalogVersion)
        let fm = FileManager.default
        try? fm.removeItem(atPath: dir)
        try fm.createDirectory(
            atPath: dir + "/rules", withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (name, data) in ruleFiles {
            let safeName = (name as NSString).lastPathComponent
            guard safeName.hasSuffix(".json"), !safeName.hasPrefix(".") else { continue }
            try data.write(to: URL(fileURLWithPath: dir + "/rules/" + safeName), options: .atomic)
        }
        try JSONIO.writeAtomically(manifest, to: dir + "/manifest.json")
    }

    /// staged を active に昇格させる（現行は previous へ退避）。
    public func promote(version: Int) throws {
        let fm = FileManager.default
        let staged = stagedDir(version: version)
        guard fm.fileExists(atPath: staged) else {
            throw QuarantineError.cannotCreate(staged)
        }
        if fm.fileExists(atPath: activeDir) {
            try? fm.removeItem(atPath: previousDir)
            try fm.moveItem(atPath: activeDir, toPath: previousDir)
        }
        try fm.createDirectory(
            atPath: (activeDir as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try fm.moveItem(atPath: staged, toPath: activeDir)
    }

    /// 1 世代前に戻す。
    public func rollback() throws -> Int? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: previousDir) else { return nil }
        let previousVersion = (try? JSONIO.read(CatalogManifest.self, at: previousDir + "/manifest.json"))?
            .catalogVersion
        try? fm.removeItem(atPath: activeDir)
        try fm.moveItem(atPath: previousDir, toPath: activeDir)
        return previousVersion
    }

    /// active のルール（差分算出と読込に使う）。
    public func activeRules() -> [Rule] {
        loadRules(dir: activeDir + "/rules")
    }

    public func stagedRules(version: Int) -> [Rule] {
        loadRules(dir: stagedDir(version: version) + "/rules")
    }

    private func loadRules(dir: String) -> [Rule] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var rules: [Rule] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: dir + "/" + name)),
                let decoded = try? JSONIO.decoder().decode([Rule].self, from: data)
            else { continue }
            rules.append(contentsOf: decoded)
        }
        return rules
    }

    /// 承認待ちを片付ける（適用済み・より新しい版の取得時）。
    public func discardStaged(olderThanOrEqual version: Int) {
        let base = env.updatesDir + "/staged"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: base) else { return }
        for name in names {
            guard let value = Int(name), value <= version else { continue }
            try? FileManager.default.removeItem(atPath: base + "/" + name)
        }
    }

    /// ダウンロード済み成果物の掃除（7 日）。
    public func pruneDownloads(now: Date = Date(), ttlDays: Int = 7) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: downloadsDir) else { return }
        for name in names {
            let path = downloadsDir + "/" + name
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                let created = attrs[.creationDate] as? Date
            else { continue }
            if now.timeIntervalSince(created) > TimeInterval(ttlDays) * 86_400 {
                try? fm.removeItem(atPath: path)
            }
        }
    }
}
