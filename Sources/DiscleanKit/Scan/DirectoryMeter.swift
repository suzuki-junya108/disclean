import Foundation

/// 1 ディレクトリの計測結果。
public struct DirectoryMeasurement: Sendable, Equatable {
    public var bytes: Int64
    public var fileCount: Int
    public var dataless: Bool
    public var blocked: Bool
    /// 中で最後に更新された時刻。「このフォルダが最近使われたか」の判断に使う。
    /// 入れ物自身の更新時刻だけを見ると、中身が何年も前でも「新しい」と誤判定する。
    public var newestModification: Date?

    public static let zero = DirectoryMeasurement(
        bytes: 0, fileCount: 0, dataless: false, blocked: false, newestModification: nil)

    mutating func note(modification: time_t) {
        let date = Date(timeIntervalSince1970: TimeInterval(modification))
        if let current = newestModification {
            newestModification = max(current, date)
        } else {
            newestModification = date
        }
    }
}

/// `readdir` + `lstat` による実割当サイズの合算。シンボリックリンクを辿らず、
/// dataless の項目は開かない（実体化を起こさない）。
public enum DirectoryMeter {
    public static func measure(path: String, isCancelled: @Sendable () -> Bool = { false }) -> DirectoryMeasurement {
        var result = DirectoryMeasurement.zero
        var st = stat()
        guard lstat(path, &st) == 0 else {
            result.blocked = errno == EPERM || errno == EACCES
            return result
        }
        if DatalessPolicy.isDataless(st) {
            result.dataless = true
            return result
        }
        if (st.st_mode & S_IFMT) != S_IFDIR {
            result.bytes = Int64(st.st_blocks) * 512
            result.fileCount = 1
            result.note(modification: st.st_mtimespec.tv_sec)
            return result
        }

        var stack = [path]
        while let current = stack.popLast() {
            if isCancelled() { break }
            guard let dir = opendir(current) else {
                if errno == EPERM || errno == EACCES { result.blocked = true }
                continue
            }
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                if isCancelled() { break }
                let name = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                let child = current + "/" + name
                var childStat = stat()
                guard lstat(child, &childStat) == 0 else {
                    if errno == EPERM || errno == EACCES { result.blocked = true }
                    continue
                }
                if DatalessPolicy.isDataless(childStat) {
                    result.dataless = true
                    continue
                }
                let mode = childStat.st_mode & S_IFMT
                if mode == S_IFDIR {
                    // 入れ物の更新時刻は数えない。中にファイルを 1 つ足しただけで
                    // 親フォルダの時刻が変わり、「最近使った」と誤判定するため。
                    stack.append(child)
                } else if mode == S_IFLNK {
                    // リンク自体のサイズだけ数え、辿らない。
                    result.bytes += Int64(childStat.st_blocks) * 512
                    result.fileCount += 1
                    result.note(modification: childStat.st_mtimespec.tv_sec)
                } else {
                    result.bytes += Int64(childStat.st_blocks) * 512
                    result.fileCount += 1
                    result.note(modification: childStat.st_mtimespec.tv_sec)
                }
            }
        }
        return result
    }
}
