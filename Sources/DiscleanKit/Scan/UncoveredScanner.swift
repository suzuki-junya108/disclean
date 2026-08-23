import Foundation

/// ルールがどれも見ていない、大きな場所。消さずに知らせるだけ。
public struct UncoveredPlace: Sendable, Equatable, Codable {
    public let path: String
    public let bytes: Int64
    public let fileCount: Int
    public let newestModification: Date?

    public init(path: String, bytes: Int64, fileCount: Int, newestModification: Date?) {
        self.path = path
        self.bytes = bytes
        self.fileCount = fileCount
        self.newestModification = newestModification
    }
}

public struct UncoveredResult: Sendable {
    public let places: [UncoveredPlace]
    /// 見に行った親フォルダ。
    public let roots: [String]
    public let minimumBytes: Int64
    /// 上限で表示を打ち切ったか（黙って減らさないため）。
    public let truncated: Bool
    /// 読めない場所があった（フルディスクアクセス未付与など）。
    public let blocked: Bool
}

/// 「ルールが 1 本も見ていないのに大きい場所」を探す。
///
/// ルールをいくら足しても、世の中のアプリすべては網羅できない。
/// ならば「見えていないこと」自体を見えるようにする方が確実で、
/// 利用者は自分の Mac で取りこぼしを見つけられる。
///
/// **絶対に消さない。** 読み取りだけを行い、結果は一覧として返す。
public struct UncoveredScanner: Sendable {
    /// 既定のしきい値。これ未満は報告しない（雑音になるため）。
    public static let defaultMinimumBytes: Int64 = 200 * 1024 * 1024

    private let env: DiscleanEnvironment
    private let config: Config
    private let guardian: PathGuard

    public init(env: DiscleanEnvironment, config: Config) {
        self.env = env
        self.config = config
        self.guardian = PathGuard(
            home: env.home, stateDir: env.stateDir, configDir: env.configDir,
            excludedPaths: config.excludedPaths)
    }

    /// キャッシュが置かれがちな親フォルダ。この直下だけを 1 段見る。
    private var roots: [String] {
        [
            env.home + "/Library/Caches",
            env.home + "/Library/Application Support",
            env.home + "/Library/Containers",
            env.home + "/Library/Group Containers",
            env.home + "/Library/Logs",
            env.home + "/Library/Developer",
            env.home + "/.cache",
            env.home,
        ]
    }

    public func scan(
        catalog: RuleCatalog,
        minimumBytes: Int64 = defaultMinimumBytes,
        limit: Int = 40,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> UncoveredResult {
        let covered = coveredPaths(catalog: catalog)
        let candidates = candidatePaths(covered: covered)

        var found: [UncoveredPlace] = []
        var blocked = false

        await withTaskGroup(of: (UncoveredPlace?, Bool).self) { group in
            var running = 0
            var iterator = candidates.makeIterator()

            func addNext() {
                guard let path = iterator.next() else { return }
                running += 1
                group.addTask {
                    let measured = DirectoryMeter.measure(path: path, isCancelled: isCancelled)
                    guard measured.bytes >= minimumBytes else { return (nil, measured.blocked) }
                    return (
                        UncoveredPlace(
                            path: path, bytes: measured.bytes, fileCount: measured.fileCount,
                            newestModification: measured.newestModification),
                        measured.blocked
                    )
                }
            }

            for _ in 0..<max(1, config.concurrency) { addNext() }
            while running > 0, let result = await group.next() {
                running -= 1
                if let place = result.0 { found.append(place) }
                blocked = blocked || result.1
                if !isCancelled() { addNext() }
            }
        }

        found.sort { $0.bytes > $1.bytes }
        let shown = Array(found.prefix(limit))
        return UncoveredResult(
            places: shown, roots: roots, minimumBytes: minimumBytes,
            truncated: found.count > shown.count, blocked: blocked)
    }

    /// いまルールが見ている場所（ひな形は広げる。ツールには聞かない＝副作用を出さない）。
    private func coveredPaths(catalog: RuleCatalog) -> [String] {
        var paths: [String] = []
        for rule in catalog.rules {
            for raw in rule.paths ?? [] {
                let expanded = PathGuard.normalize(Expand.tilde(raw, home: env.home))
                if PathPattern.hasWildcard(expanded) {
                    paths.append(contentsOf: PathPattern.expand(expanded))
                } else {
                    paths.append(expanded)
                }
            }
        }
        return paths
    }

    /// 見に行く先を決める。
    ///
    /// - すでにルールが見ている場所は外す
    /// - ルールが「一部だけ」見ている場所（中に対象がある）は、1 段下りて残りを見る。
    ///   親ごと隠すと、隣にある未対応の大物が見えなくなる
    /// - 自分の保存先（隔離庫）を含む場所も、同じように 1 段下りる
    private func candidatePaths(covered: [String]) -> [String] {
        var candidates: [String] = []
        let selfPaths = [env.stateDir, env.configDir].map { PathGuard.normalize($0) }

        func consider(_ path: String, depth: Int) {
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return }
            // 見てよい範囲（ホーム配下・除外されていない）だけを扱う。読み取りだけなので深さは問わない。
            guard guardian.canInspect(path, quarantineDir: env.quarantineDir) else { return }
            if selfPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return }

            // まるごとルールの中にある場合は、報告しない
            if covered.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return }

            let holdsSomethingKnown =
                covered.contains { $0.hasPrefix(path + "/") }
                || selfPaths.contains { $0.hasPrefix(path + "/") }
            if holdsSomethingKnown && depth < 2 {
                for child in children(of: path) { consider(child, depth: depth + 1) }
                return
            }
            candidates.append(path)
        }

        for root in roots {
            for path in children(of: root) {
                let name = String(path.dropFirst(root.count + 1))
                // ホーム直下は、隠しフォルダだけを見る（書類やデスクトップは対象外）
                if root == env.home && !name.hasPrefix(".") { continue }
                if name == ".Trash" { continue }
                consider(PathGuard.normalize(path), depth: 0)
            }
        }
        return candidates
    }

    private func children(of directory: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return names.sorted().map { directory + "/" + $0 }
    }
}
