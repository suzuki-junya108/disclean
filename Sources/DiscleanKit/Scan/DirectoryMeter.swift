import Foundation

/// 1 ディレクトリの計測結果。
public struct DirectoryMeasurement: Sendable, Equatable {
    public var bytes: Int64
    public var fileCount: Int
    public var dataless: Bool
    public var blocked: Bool

    public static let zero = DirectoryMeasurement(bytes: 0, fileCount: 0, dataless: false, blocked: false)
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
                    stack.append(child)
                } else if mode == S_IFLNK {
                    // リンク自体のサイズだけ数え、辿らない。
                    result.bytes += Int64(childStat.st_blocks) * 512
                    result.fileCount += 1
                } else {
                    result.bytes += Int64(childStat.st_blocks) * 512
                    result.fileCount += 1
                }
            }
        }
        return result
    }
}
