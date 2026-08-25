import Foundation

/// 探した結果。見つからなかった理由も一緒に返す（黙って 0 件にしない）。
public struct BigItemResult: Sendable {
    /// 大きい順。`limit` 件まで。
    public let items: [BigItem]
    /// 見に行った場所。
    public let roots: [String]
    public let minimumBytes: Int64
    /// 上限で打ち切ったか。
    public let truncated: Bool
    /// 読めない場所があった（フルディスクアクセス未付与など）。
    public let blocked: Bool
    /// まだ手元に降りていないもの（iCloud）があった。開かずに飛ばしている。
    public let datalessSkipped: Bool
    /// 見たエントリ数。「探したけれど無かった」ことを数で言えるようにする。
    public let scannedEntries: Int
    /// 途中でやめた。「見つかりませんでした」と混同させない。
    public let interrupted: Bool

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    public init(
        items: [BigItem], roots: [String], minimumBytes: Int64, truncated: Bool, blocked: Bool,
        datalessSkipped: Bool, scannedEntries: Int, interrupted: Bool
    ) {
        self.items = items
        self.roots = roots
        self.minimumBytes = minimumBytes
        self.truncated = truncated
        self.blocked = blocked
        self.datalessSkipped = datalessSkipped
        self.scannedEntries = scannedEntries
        self.interrupted = interrupted
    }
}

/// 書類側（ホームの見えるフォルダ）にある大きいものを探す。読み取りだけを行う。
///
/// `UncoveredScanner` が「ルールが見ていない**場所**」を 1 段だけ見るのに対して、
/// こちらは奥まで下りて「大きい**もの**」を持ち主ごとにまとめて拾う。
/// 見つけたものを消すかどうかは、必ず人が 1 件ずつ選ぶ（既定では 1 件も選ばれない）。
public struct BigItemScanner: Sendable {
    /// 既定のしきい値。`report --unknown` と同じ 200MB にそろえる。
    public static let defaultMinimumBytes: Int64 = 200 * 1024 * 1024
    public static let defaultLimit = 60
    /// 進みぐあいの報せに載せる名前（ルール ID ではないが、同じ枠で流す）。
    public static let progressRuleId = "big-item"

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

    /// 既定で見に行く場所＝ホーム直下の、見えるフォルダ。
    ///
    /// - `~/Library` は既存ルールと `report --unknown` の担当なので既定では見ない。
    /// - 隠しフォルダ（`.` 始まり）も同じ理由で見ない。
    /// - ホーム直下に**直に置かれたファイル**（`~/big.dmg`）は対象にしない。
    ///   隔離庫へ移せるのはホームから 2 段以上深いものだけ（`PathGuard` SG-02）で、
    ///   探せても片づけられないものを一覧に混ぜると嘘になるため。
    public func defaultRoots(includeLibrary: Bool = false) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: env.home))?.sorted() ?? []
        var roots: [String] = []
        for name in names {
            if name.hasPrefix(".") { continue }
            if name == "Library" && !includeLibrary { continue }
            let path = PathGuard.normalize(env.home + "/" + name)
            guard isUsableRoot(path) else { continue }
            roots.append(path)
        }
        return roots
    }

    /// 利用者が書いた場所を、この道具が扱う形にそろえる（`~` を開き、末尾の `/` を落とす）。
    public func resolve(_ raw: String) -> String {
        PathGuard.normalize(Expand.tilde(raw, home: env.home))
    }

    /// 読み取り目的で中を見てよい場所か。消してよいかどうかとは別の判断。
    public func canInspect(_ path: String) -> Bool {
        guardian.canInspect(path, quarantineDir: env.quarantineDir) && !isSelfPath(path)
    }

    /// 見に行ってよいフォルダか（存在する・ディレクトリ・自分の保存先ではない）。
    public func isUsableRoot(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return false }
        return canInspect(path)
    }

    public func scan(
        roots explicitRoots: [String] = [],
        minimumBytes: Int64 = defaultMinimumBytes,
        limit: Int = defaultLimit,
        includeLibrary: Bool = false,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping WorkProgressHandler = ignoreProgress
    ) async -> BigItemResult {
        let roots = explicitRoots.isEmpty ? defaultRoots(includeLibrary: includeLibrary) : explicitRoots
        var found: [BigItem] = []
        var blocked = false
        var dataless = false
        var scanned = 0

        await withTaskGroup(of: Findings.self) { group in
            var running = 0
            var iterator = roots.makeIterator()

            func addNext() {
                guard let root = iterator.next() else { return }
                running += 1
                let walker = BigItemWalker(
                    minimumBytes: minimumBytes, guardian: guardian,
                    quarantineDir: env.quarantineDir, selfPaths: selfPaths,
                    isCancelled: isCancelled, onProgress: onProgress)
                group.addTask { walker.walk(root: root) }
            }

            for _ in 0..<max(1, config.concurrency) { addNext() }
            while running > 0, let findings = await group.next() {
                running -= 1
                found.append(contentsOf: findings.items)
                blocked = blocked || findings.blocked
                dataless = dataless || findings.dataless
                scanned += findings.scanned
                if !isCancelled() { addNext() }
            }
        }

        found.sort { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }
        let shown = Array(found.prefix(limit))
        return BigItemResult(
            items: shown, roots: roots, minimumBytes: minimumBytes,
            truncated: found.count > shown.count, blocked: blocked, datalessSkipped: dataless,
            scannedEntries: scanned, interrupted: isCancelled())
    }

    /// 自分の保存先（隔離庫・設定）。`canInspect` は隔離庫を許すので、ここで別に外す。
    private var selfPaths: [String] {
        [env.stateDir, env.configDir].map { PathGuard.normalize($0) }
    }

    private func isSelfPath(_ path: String) -> Bool {
        selfPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

/// 1 つの根を歩いた結果。
private struct Findings: Sendable {
    var items: [BigItem] = []
    var blocked = false
    var dataless = false
    var scanned = 0
}

/// ハードリンクで同じ実体を指すものを二重に数えないための鍵。
private struct LinkKey: Hashable {
    let device: dev_t
    let inode: ino_t
}

/// 1 つの根を奥まで歩く道具。持ち回る値をまとめて持つ。
///
/// `readdir` + `lstat` だけで、中身は開かない。同じ実体を指すハードリンクは
/// 1 回だけ数える（数え方は根ごとに閉じる）。
private struct BigItemWalker: Sendable {
    let minimumBytes: Int64
    let guardian: PathGuard
    let quarantineDir: String
    let selfPaths: [String]
    let isCancelled: @Sendable () -> Bool
    let onProgress: WorkProgressHandler

    func walk(root: String) -> Findings {
        var findings = Findings()
        var seenLinks = Set<LinkKey>()
        var stack = [root]

        while let current = stack.popLast() {
            if isCancelled() { break }
            onProgress(
                WorkProgress(step: .measuring, ruleId: BigItemScanner.progressRuleId, path: current))
            guard let dir = opendir(current) else {
                if errno == EPERM || errno == EACCES { findings.blocked = true }
                continue
            }
            defer { closedir(dir) }

            while let raw = readdir(dir) {
                if isCancelled() { break }
                let name = Self.name(of: raw)
                if name == "." || name == ".." { continue }
                findings.scanned += 1
                if let descend = visit(
                    path: current + "/" + name, name: name, links: &seenLinks, into: &findings)
                {
                    stack.append(descend)
                }
            }
        }
        return findings
    }

    /// 1 件を見る。さらに下りるべきフォルダなら、その場所を返す。
    private func visit(
        path: String, name: String, links: inout Set<LinkKey>, into findings: inout Findings
    ) -> String? {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            if errno == EPERM || errno == EACCES { findings.blocked = true }
            return nil
        }
        // まだ手元に降りていないもの（iCloud）は開かない。開くと降ろしてしまう。
        if DatalessPolicy.isDataless(st) {
            findings.dataless = true
            return nil
        }
        let mode = st.st_mode & S_IFMT
        // リンクは辿らない。辿ると同じものを二重に数え、輪になると終わらない。
        if mode == S_IFLNK { return nil }
        if mode == S_IFDIR { return visitDirectory(path: path, name: name, into: &findings) }
        guard mode == S_IFREG else { return nil }

        let bytes = Int64(st.st_blocks) * 512
        guard bytes >= minimumBytes else { return nil }
        if st.st_nlink > 1 {
            guard links.insert(LinkKey(device: st.st_dev, inode: st.st_ino)).inserted else { return nil }
        }
        let kind = FileKind.infer(name: name, isDirectory: false)
        let advice = BigItemMarkers.advice(group: .file, marker: nil, kind: kind)
        findings.items.append(
            BigItem(
                path: path, name: name, bytes: bytes, fileCount: 1, isDirectory: false,
                modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
                kind: kind, group: .file, marker: nil, adviceJa: advice.ja, advice: advice.en))
        return nil
    }

    /// フォルダを見る。目印に当たれば 1 件にまとめ、当たらなければ下りる場所として返す。
    private func visitDirectory(path: String, name: String, into findings: inout Findings) -> String? {
        guard guardian.canInspect(path, quarantineDir: quarantineDir),
            !selfPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
        else { return nil }

        if let marker = BigItemMarkers.bundle(for: name) {
            appendMeasured(path: path, name: name, group: .bundle, marker: marker, into: &findings)
            return nil
        }
        if let marker = BigItemMarkers.parts(for: name) {
            appendMeasured(path: path, name: name, group: .parts, marker: marker, into: &findings)
            return nil
        }
        return path
    }

    /// 入れ物を 1 件として測って積む。しきい値に満たなければ何も積まない（中へは下りない）。
    private func appendMeasured(
        path: String, name: String, group: BigItemGroup, marker: String, into findings: inout Findings
    ) {
        let measured = DirectoryMeter.measure(path: path, isCancelled: isCancelled)
        findings.blocked = findings.blocked || measured.blocked
        findings.dataless = findings.dataless || measured.dataless
        findings.scanned += measured.fileCount
        guard measured.bytes >= minimumBytes else { return }
        let advice = BigItemMarkers.advice(group: group, marker: marker, kind: .folder)
        findings.items.append(
            BigItem(
                path: path, name: name, bytes: measured.bytes, fileCount: measured.fileCount,
                isDirectory: true, modified: measured.newestModification, kind: .folder,
                group: group, marker: marker, adviceJa: advice.ja, advice: advice.en))
    }

    private static func name(of entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                String(cString: $0)
            }
        }
    }
}
