import Foundation

/// ファイルの種類。名前と拡張子から推定する（中身は開かない）。
///
/// 目的は分類そのものではなく、「これは何で、消えると何が起きるか」を
/// ふつうの言葉で言えるようにすること。
public enum FileKind: String, Codable, Sendable, CaseIterable {
    case folder
    case archive
    case image
    case video
    case audio
    case log
    case database
    case code
    case buildArtifact
    case contentBlob
    case document
    case other

    public var labelJa: String {
        switch self {
        case .folder: "フォルダ"
        case .archive: "圧縮ファイル"
        case .image: "画像"
        case .video: "動画"
        case .audio: "音声"
        case .log: "ログ"
        case .database: "データベース"
        case .code: "プログラム"
        case .buildArtifact: "ビルドの出力"
        case .contentBlob: "キャッシュの中身"
        case .document: "文書・設定"
        case .other: "その他"
        }
    }

    public var label: String {
        switch self {
        case .folder: "Folder"
        case .archive: "Archive"
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .log: "Log"
        case .database: "Database"
        case .code: "Source"
        case .buildArtifact: "Build output"
        case .contentBlob: "Cached blob"
        case .document: "Document"
        case .other: "Other"
        }
    }

    /// 「消えると何が起きるか」を 1 文で。
    public var explanationJa: String {
        switch self {
        case .folder: "中にファイルが入っています。開いて中身を確かめられます。"
        case .archive: "ダウンロードした部品を固めたものです。次に必要になれば取り直します。"
        case .image: "画像です。元が手元にしか無いものかどうか、開いて確かめてください。"
        case .video: "動画です。元が手元にしか無いものかどうか、開いて確かめてください。"
        case .audio: "音声です。元が手元にしか無いものかどうか、開いて確かめてください。"
        case .log: "動いた記録です。消しても、これからの動作には影響しません。"
        case .database: "検索を速くするための索引です。消すと作り直され、初回だけ遅くなります。"
        case .code: "プログラムの元の文です。作業中のものが含まれていないか確かめてください。"
        case .buildArtifact: "ビルドで作られたものです。次のビルドで作り直されます。"
        case .contentBlob: "取得したものの実体です。名前は中身から作った番号で、意味はありません。"
        case .document: "設定や覚え書きです。中身を開いて確かめられます。"
        case .other: "種類を判別できませんでした。開いて確かめられます。"
        }
    }

    public var explanation: String {
        switch self {
        case .folder: "A folder. Open it to see what is inside."
        case .archive: "A downloaded package. It is fetched again when needed."
        case .image: "An image. Check whether the original exists elsewhere."
        case .video: "A video. Check whether the original exists elsewhere."
        case .audio: "Audio. Check whether the original exists elsewhere."
        case .log: "A record of what happened. Removing it changes nothing going forward."
        case .database: "An index that makes lookups fast. It is rebuilt when removed."
        case .code: "Source text. Make sure none of your work in progress is here."
        case .buildArtifact: "Produced by a build. The next build recreates it."
        case .contentBlob: "The body of something fetched. The name is a content hash."
        case .document: "Settings or notes. You can open it and read it."
        case .other: "Unrecognised. You can open it and check."
        }
    }

    /// 拡張子とファイル名から推定する。
    public static func infer(name: String, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        let lower = name.lowercased()
        for (kind, suffixes) in suffixTable {
            for suffix in suffixes where lower.hasSuffix(suffix) { return kind }
        }
        // 拡張子が無く、名前が 16 文字以上の 16 進数ならキャッシュの実体（content-addressed）。
        if !lower.contains("."), lower.count >= 16,
            lower.allSatisfy({ $0.isHexDigit })
        {
            return .contentBlob
        }
        return .other
    }

    /// 先に書いたものが勝つ。`.tar.gz` を `.gz` より先に見たいので配列で持つ。
    private static let suffixTable: [(FileKind, [String])] = [
        (
            .archive,
            [
                ".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".zip", ".gz", ".bz2", ".xz", ".7z",
                ".whl", ".jar", ".rar", ".tar",
            ]
        ),
        (.image, [".png", ".jpg", ".jpeg", ".gif", ".heic", ".webp", ".tiff", ".bmp", ".svg", ".icns"]),
        (.video, [".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm"]),
        (.audio, [".mp3", ".m4a", ".wav", ".aiff", ".flac", ".aac"]),
        (.log, [".log", ".log.gz", ".crash", ".diag", ".ips"]),
        (.database, [".db", ".sqlite", ".sqlite3", ".realm", ".idx", ".index", ".pack"]),
        (
            .buildArtifact,
            [
                ".o", ".a", ".dylib", ".so", ".swiftmodule", ".swiftdoc", ".swiftsourceinfo",
                ".dSYM", ".bc", ".pyc", ".class", ".tbd", ".build", ".pcm",
            ]
        ),
        (
            .code,
            [
                ".swift", ".c", ".h", ".m", ".mm", ".cpp", ".hpp", ".js", ".ts", ".tsx", ".jsx",
                ".py", ".rb", ".go", ".rs", ".sh", ".java", ".kt",
            ]
        ),
        (
            .document,
            [
                ".json", ".plist", ".yaml", ".yml", ".toml", ".txt", ".md", ".xml", ".pdf", ".csv",
                ".cfg", ".ini", ".lock",
            ]
        ),
    ]
}

/// 一覧に出す 1 行。ファイル 1 つ、またはフォルダ 1 つ。
public struct InventoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let path: String
    public let name: String
    public let bytes: Int64
    public let isDirectory: Bool
    public let isSymlink: Bool
    /// フォルダなら中のファイル数。ファイルなら 1。
    public let fileCount: Int
    public let modified: Date?
    public let kind: FileKind

    public var id: String { path }

    public init(
        path: String, name: String, bytes: Int64, isDirectory: Bool, isSymlink: Bool,
        fileCount: Int, modified: Date?, kind: FileKind
    ) {
        self.path = path
        self.name = name
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.fileCount = fileCount
        self.modified = modified
        self.kind = kind
    }
}

/// 1 つの場所（または複数の場所）の中身。
public struct Inventory: Codable, Sendable, Equatable {
    /// 大きい順。`limit` 件まで。
    public let entries: [InventoryEntry]
    /// この場所にあるものの合計。`entries` に出していない分も含む。
    public let totalBytes: Int64
    public let totalFiles: Int
    /// 一覧に出していない件数。
    public let hiddenCount: Int
    /// 読めない場所があった（フルディスクアクセス未付与など）。
    public let blocked: Bool
    /// 場所そのものが無かった。
    public let notFound: Bool

    public static let empty = Inventory(
        entries: [], totalBytes: 0, totalFiles: 0, hiddenCount: 0, blocked: false, notFound: true)

    public init(
        entries: [InventoryEntry], totalBytes: Int64, totalFiles: Int, hiddenCount: Int,
        blocked: Bool, notFound: Bool
    ) {
        self.entries = entries
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
        self.hiddenCount = hiddenCount
        self.blocked = blocked
        self.notFound = notFound
    }
}

/// 「この場所には何が入っているのか」を、1 段だけ開いて見せる。
///
/// 全部を再帰的に平らに並べると、数万件の羅列になって逆に分からなくなる。
/// 1 段ずつ、大きい順に見せて、フォルダは選んでさらに開く。
public enum FileInventory {
    public static let defaultLimit = 40

    public static func list(
        paths: [String], limit: Int = defaultLimit, isCancelled: @Sendable () -> Bool = { false }
    ) -> Inventory {
        var entries: [InventoryEntry] = []
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var blocked = false
        var found = false

        for path in paths {
            if isCancelled() { break }
            var st = stat()
            guard lstat(path, &st) == 0 else {
                if errno == EPERM || errno == EACCES { blocked = true }
                continue
            }
            found = true
            if (st.st_mode & S_IFMT) == S_IFDIR {
                let level = children(of: path, isCancelled: isCancelled)
                entries.append(contentsOf: level.entries)
                totalBytes += level.bytes
                totalFiles += level.files
                blocked = blocked || level.blocked
            } else {
                // 場所そのものがファイルなら、それ 1 件を見せる。
                let entry = makeEntry(path: path, name: displayName(of: path), stat: st, isCancelled: isCancelled)
                entries.append(entry)
                totalBytes += entry.bytes
                totalFiles += entry.fileCount
            }
        }

        entries.sort { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }
        let shown = Array(entries.prefix(limit))
        return Inventory(
            entries: shown,
            totalBytes: totalBytes,
            totalFiles: totalFiles,
            hiddenCount: max(0, entries.count - shown.count),
            blocked: blocked,
            notFound: !found)
    }

    /// 1 段分の読み取り結果。
    private struct Level {
        var entries: [InventoryEntry] = []
        var bytes: Int64 = 0
        var files = 0
        var blocked = false
    }

    private static func children(of directory: String, isCancelled: @Sendable () -> Bool) -> Level {
        guard let dir = opendir(directory) else {
            return Level(blocked: errno == EPERM || errno == EACCES)
        }
        defer { closedir(dir) }

        var level = Level()

        while let raw = readdir(dir) {
            if isCancelled() { break }
            let name = withUnsafePointer(to: raw.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(raw.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            let child = directory + "/" + name
            var childStat = stat()
            guard lstat(child, &childStat) == 0 else {
                if errno == EPERM || errno == EACCES { level.blocked = true }
                continue
            }
            let entry = makeEntry(path: child, name: name, stat: childStat, isCancelled: isCancelled)
            level.entries.append(entry)
            level.bytes += entry.bytes
            level.files += entry.fileCount
        }
        return level
    }

    private static func makeEntry(
        path: String, name: String, stat st: stat, isCancelled: @Sendable () -> Bool
    ) -> InventoryEntry {
        let mode = st.st_mode & S_IFMT
        let isDirectory = mode == S_IFDIR
        let isSymlink = mode == S_IFLNK

        if isDirectory {
            // フォルダは中身を数え上げる。実割当（st_blocks）で数えるので、
            // 一覧の合計と実行時に動く量が一致する。
            let measured = DirectoryMeter.measure(path: path, isCancelled: isCancelled)
            return InventoryEntry(
                path: path, name: name, bytes: measured.bytes, isDirectory: true, isSymlink: false,
                fileCount: measured.fileCount,
                modified: measured.newestModification,
                kind: .folder)
        }

        return InventoryEntry(
            path: path, name: name, bytes: Int64(st.st_blocks) * 512, isDirectory: false,
            isSymlink: isSymlink, fileCount: 1,
            modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
            kind: isSymlink ? .other : FileKind.infer(name: name, isDirectory: false))
    }

    private static func displayName(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
