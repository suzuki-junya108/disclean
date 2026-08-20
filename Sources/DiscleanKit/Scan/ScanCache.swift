import Foundation

/// ディレクトリ単位の計測キャッシュ（24 時間 + mtime 一致で再利用）。
public struct ScanCache: Codable, Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public let bytes: Int64
        public let fileCount: Int
        public let mtime: Double
        public let measuredAt: Date
    }

    public var schemaVersion: Int = 1
    public var entries: [String: Entry] = [:]

    public static let ttl: TimeInterval = 24 * 60 * 60

    public init() {}

    public static func load(path: String) -> ScanCache {
        (try? JSONIO.read(ScanCache.self, at: path)) ?? ScanCache()
    }

    public func save(path: String) {
        try? JSONIO.writeAtomically(self, to: path)
    }

    public func lookup(path: String, now: Date = Date()) -> Entry? {
        guard let entry = entries[path] else { return nil }
        guard now.timeIntervalSince(entry.measuredAt) < ScanCache.ttl else { return nil }
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let mtime = Double(st.st_mtimespec.tv_sec)
        guard mtime == entry.mtime else { return nil }
        return entry
    }

    public mutating func store(path: String, bytes: Int64, fileCount: Int, now: Date = Date()) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        entries[path] = Entry(
            bytes: bytes, fileCount: fileCount, mtime: Double(st.st_mtimespec.tv_sec), measuredAt: now)
    }

    /// OS が変わったらキャッシュは信用しない（パスの意味が変わりうるため）。
    public mutating func clear() { entries.removeAll() }
}
