import Foundation

/// ルールに書く場所の「ひな形」。`*` と `?` を 1 階層の中だけで使える。
///
/// キャッシュの置き場所は、機械ごとに変わる ID の下にあることが多い
/// （シミュレータの端末 ID、アプリのコンテナ ID など）。決め打ちで書くと
/// その 1 台でしか当たらないため、ひな形で書けるようにする。
///
/// `**`（階層をまたぐ）は用意しない。深いところまで一気に当てると、
/// 意図しない場所まで巻き込む事故が起きやすいため、必ず 1 階層ずつ当てる。
public enum PathPattern {
    /// ひな形 1 本から広げる上限。壊れたひな形で数万件に広がるのを止める。
    public static let expansionLimit = 4096

    public static func hasWildcard(_ pattern: String) -> Bool {
        pattern.contains("*") || pattern.contains("?")
    }

    /// ひな形に当てはまる場所を、実在するものだけ返す。
    ///
    /// - 各段は `readdir` で 1 階層だけ見る
    /// - **途中の段がリンクなら、その先へは進まない**（辿ると範囲外へ出られる）
    /// - 最後に当たったものがリンクなら結果に入れない（実行時にどのみち拒否される）
    /// - 隠しファイルは、ひな形が `.` で始まる段でだけ当てる（`*` で `.git` を巻き込まない）
    /// 広げた結果。上限で打ち切ったかどうかも返す（黙って減らさない）。
    public struct Expansion: Sendable, Equatable {
        public let paths: [String]
        public let truncated: Bool
    }

    public static func expand(
        _ pattern: String, isCancelled: @Sendable () -> Bool = { false }
    ) -> [String] {
        expandDetailed(pattern, isCancelled: isCancelled).paths
    }

    public static func expandDetailed(
        _ pattern: String, isCancelled: @Sendable () -> Bool = { false }
    ) -> Expansion {
        guard hasWildcard(pattern) else {
            return Expansion(paths: isRealTarget(pattern) ? [pattern] : [], truncated: false)
        }
        // ワイルドカードより前（ルールに書かれた固定部分）は、リンクを解決してから歩き出す。
        // `/tmp` → `/private/tmp` のように、固定部分自体がリンクであることは普通にある。
        // 解決するのはここだけで、広げる途中で出てきたリンクは辿らない。
        let prefix = staticPrefix(pattern)
        guard isRealDirectory((prefix as NSString).resolvingSymlinksInPath) else {
            return Expansion(paths: [], truncated: false)
        }
        let base = (prefix as NSString).resolvingSymlinksInPath
        let rest = String(pattern.dropFirst(prefix.count))
        let segments = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = [base]

        var truncated = false
        for (index, segment) in segments.enumerated() {
            if isCancelled() { return Expansion(paths: [], truncated: truncated) }
            let step = match(
                segment: segment, in: current, isLast: index == segments.count - 1,
                isCancelled: isCancelled)
            truncated = truncated || step.truncated
            current = step.paths
            if current.isEmpty { return Expansion(paths: [], truncated: truncated) }
        }
        return Expansion(paths: current, truncated: truncated)
    }

    /// 1 段ぶんだけ当てはめる。最後の段以外は、本物のフォルダにしか進まない。
    private static func match(
        segment: String, in parents: [String], isLast: Bool, isCancelled: @Sendable () -> Bool
    ) -> Expansion {
        var next: [String] = []
        guard hasWildcard(segment) else {
            for parent in parents {
                let child = parent + "/" + segment
                if isLast ? isRealTarget(child) : isRealDirectory(child) { next.append(child) }
            }
            return Expansion(paths: next, truncated: false)
        }

        for parent in parents {
            if isCancelled() { return Expansion(paths: next, truncated: false) }
            for name in entries(of: parent) {
                // `*` は隠し項目に当てない。ひな形側が `.` で始まるときだけ当てる。
                if name.hasPrefix("."), !segment.hasPrefix(".") { continue }
                guard fnmatch(segment, name, FNM_PERIOD) == 0 else { continue }
                let child = parent + "/" + name
                guard isLast ? isRealTarget(child) : isRealDirectory(child) else { continue }
                next.append(child)
                if next.count >= expansionLimit { return Expansion(paths: next, truncated: true) }
            }
        }
        return Expansion(paths: next, truncated: false)
    }

    /// ひな形のうち、ワイルドカードが出てくる前までの部分。
    /// カタログの検証は、この固定部分に対して行う（実物が無くても検査できる）。
    public static func staticPrefix(_ pattern: String) -> String {
        var kept: [String] = []
        for segment in pattern.split(separator: "/", omittingEmptySubsequences: false) {
            if hasWildcard(String(segment)) { break }
            kept.append(String(segment))
        }
        let joined = kept.joined(separator: "/")
        return joined.isEmpty ? pattern : joined
    }

    /// 実体があり、リンクではないか（リンクは対象にしない）。
    private static func isRealTarget(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) != S_IFLNK
    }

    /// 本物のフォルダか。途中の段がこれを満たさなければ、そこで止める。
    private static func isRealDirectory(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// 1 階層分の名前。リンクは名前としては返すが、辿った先は見ない。
    private static func entries(of directory: String) -> [String] {
        guard let dir = opendir(directory) else { return [] }
        defer { closedir(dir) }
        var names: [String] = []
        while let raw = readdir(dir) {
            let name = withUnsafePointer(to: raw.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(raw.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            names.append(name)
        }
        return names.sorted()
    }
}
