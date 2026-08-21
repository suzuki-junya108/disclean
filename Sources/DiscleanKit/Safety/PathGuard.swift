import Foundation

/// 安全ガード違反の理由（要件 §4.2 F-05 の SG-01〜SG-09）。
public enum GuardViolation: String, Sendable, Equatable {
    case outsideHome = "outside-home"
    case tooShallow = "too-shallow"
    case forbiddenRoot = "forbidden-root"
    case symlink
    case selfReferential = "self-referential"
    case excluded
    case appRunning = "app-running"
    case crossVolume = "cross-volume"
    case tooRecent = "too-recent"
    case notFound = "not-found"
}

/// 削除実行の直前に適用するパス検証。すべての破壊的操作はここを通る。
public struct PathGuard: Sendable {
    public let home: String
    public let stateDir: String
    public let configDir: String
    public let excludedPaths: [String]

    private static let forbiddenPrefixes = [
        "/System", "/Library", "/private/var", "/usr", "/bin", "/sbin", "/Applications",
    ]

    public init(home: String, stateDir: String, configDir: String, excludedPaths: [String]) {
        // 比較は実体パスで行う（/var → /private/var のような symlink 差で判定がぶれないように）。
        let resolvedHome = PathGuard.resolve(home)
        self.home = resolvedHome
        self.stateDir = PathGuard.resolve(stateDir)
        self.configDir = PathGuard.resolve(configDir)
        self.excludedPaths = excludedPaths.map { PathGuard.resolve(Expand.tilde($0, home: resolvedHome)) }
    }

    /// 末尾スラッシュを落とし、`.` 成分を畳む（シンボリックリンクは解決しない）。
    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// リンクを解決した実体パス。解決できない場合は正規化した入力を返す。
    static func resolve(_ path: String) -> String {
        let resolved = (path as NSString).resolvingSymlinksInPath
        return normalize(resolved)
    }

    /// `child` が `parent` の配下（または一致）かどうか。
    static func isUnder(_ child: String, _ parent: String) -> Bool {
        let c = normalize(child)
        let p = normalize(parent)
        return c == p || c.hasPrefix(p.hasSuffix("/") ? p : p + "/")
    }

    /// ルール定義の時点で拒否すべきパスか（F-01 の検証）。
    /// 実体の有無を見ないため、スキャン前・カタログ読込時に使える。
    public func validateRulePath(_ rawPath: String) -> GuardViolation? {
        let expanded = PathGuard.resolve(Expand.tilde(rawPath, home: home))
        if expanded.isEmpty || expanded == "/" { return .forbiddenRoot }
        guard PathGuard.isUnder(expanded, home) else {
            // ホームの外は一切触らない。システム領域はその中でも特に明示して弾く。
            for prefix in PathGuard.forbiddenPrefixes where PathGuard.isUnder(expanded, prefix) {
                return .forbiddenRoot
            }
            return .outsideHome
        }
        if depthFromHome(expanded) < 2 { return .tooShallow }
        if PathGuard.isUnder(expanded, stateDir) || PathGuard.isUnder(expanded, configDir) { return .selfReferential }
        for excluded in excludedPaths where PathGuard.isUnder(expanded, excluded) { return .excluded }
        return nil
    }

    /// 実行直前の検証。`lstat` でリンクを判定し、実体の状態まで見る。
    /// - Parameter newestModification: ディレクトリの場合、その中で最後に更新された時刻。
    ///   渡さなければ入れ物自身の更新時刻で判定する。
    public func validateForRemoval(
        path: String,
        minAgeDays: Int?,
        now: Date = Date(),
        sameVolumeAs quarantineDir: String? = nil,
        newestModification: Date? = nil
    ) -> GuardViolation? {
        let expanded = PathGuard.normalize(Expand.tilde(path, home: home))

        // SG-04: 対象自身がシンボリックリンクなら辿らずに拒否する。
        var st = stat()
        guard lstat(expanded, &st) == 0 else { return .notFound }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }

        // SG-01〜03, 05, 06: 静的な規則は realpath 解決後の値で再検証する。
        let resolved = PathGuard.resolve(expanded)
        if let violation = validateRulePath(resolved) { return violation }
        if let violation = validateRulePath(expanded) { return violation }

        // SG-09: 最近使われたものは触らない。
        if let minAgeDays {
            let lastUsed =
                newestModification ?? Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            let ageDays = now.timeIntervalSince(lastUsed) / 86_400
            if ageDays < Double(minAgeDays) { return .tooRecent }
        }

        // SG-08: 隔離庫と同一ボリュームでなければ移動しない（コピーへ退避しない）。
        if let quarantineDir {
            var qst = stat()
            if stat(quarantineDir, &qst) == 0, qst.st_dev != st.st_dev { return .crossVolume }
        }
        return nil
    }

    private func depthFromHome(_ path: String) -> Int {
        guard PathGuard.isUnder(path, home) else { return 0 }
        let rest = String(path.dropFirst(home.count)).split(separator: "/")
        return rest.count
    }
}

/// `~` 展開のユーティリティ。
public enum Expand {
    public static func tilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }
}
