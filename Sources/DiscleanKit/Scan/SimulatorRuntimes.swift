import Foundation

/// 入っているシミュレータ本体（ランタイムのディスクイメージ）1 つ。
public struct SimulatorRuntime: Sendable, Equatable {
    /// イメージの識別子（UUID）。`simctl runtime delete` の dry-run はこれで対象を示す。
    public let identifier: String
    /// 端末が結びつく版の識別子（例 `com.apple.CoreSimulator.SimRuntime.iOS-26-1`）。
    public let runtimeIdentifier: String
    public let version: String
    public let build: String
    public let sizeBytes: Int64
    public let lastUsedAt: Date?

    public init(
        identifier: String, runtimeIdentifier: String, version: String, build: String, sizeBytes: Int64,
        lastUsedAt: Date?
    ) {
        self.identifier = identifier
        self.runtimeIdentifier = runtimeIdentifier
        self.version = version
        self.build = build
        self.sizeBytes = sizeBytes
        self.lastUsedAt = lastUsedAt
    }

    /// 人が読む名前（例 "iOS 26.1（23B86）"）。
    public func name(japanese: Bool) -> String {
        let platform =
            runtimeIdentifier
            .components(separatedBy: "SimRuntime.").last?
            .split(separator: "-").first.map(String.init) ?? "Simulator"
        return japanese ? "\(platform) \(version)（\(build)）" : "\(platform) \(version) (\(build))"
    }
}

/// 片づける対象になった本体 1 つと、消すと一緒に起きること。
public struct SimulatorRuntimeTarget: Sendable, Equatable {
    public let runtime: SimulatorRuntime
    /// この本体のために作られた共有キャッシュ（dyld shared cache）の量。本体と一緒に消える。
    public let cacheBytes: Int64
    /// この本体が消えると動かせなくなる端末の数。分からなければ nil。
    public let devicesLosingRuntime: Int?
    /// 「古いビルド」の片づけにも含まれている（両方えらんでも 1 回ぶんしか空かない）。
    public let alsoOutdated: Bool

    public var totalBytes: Int64 { runtime.sizeBytes + cacheBytes }

    /// 消す前に読む 1 行。何が・どれだけ・いつから使っていないか・何が巻き込まれるか。
    public func describe(japanese: Bool) -> String {
        var parts: [String] = []
        let size = ByteText.string(runtime.sizeBytes)
        if cacheBytes > 0 {
            let cache = ByteText.string(cacheBytes)
            parts.append(
                japanese
                    ? "\(runtime.name(japanese: true)) \(size) ＋ 共有キャッシュ \(cache)"
                    : "\(runtime.name(japanese: false)) \(size) + shared cache \(cache)")
        } else {
            parts.append("\(runtime.name(japanese: japanese)) \(size)")
        }
        if let lastUsedAt = runtime.lastUsedAt {
            let day = SimulatorRuntimes.dayText(lastUsedAt)
            parts.append(japanese ? "最後に使った日 \(day)" : "last used \(day)")
        } else {
            parts.append(japanese ? "使った記録がありません" : "no record of use")
        }
        if let devices = devicesLosingRuntime, devices > 0 {
            parts.append(
                japanese
                    ? "この版の端末 \(devices) 台が使えなくなります"
                    : "\(devices) device(s) on this version stop working")
        }
        if alsoOutdated {
            parts.append(
                japanese
                    ? "「古いビルド」の片づけにも入っています（両方えらんでも空くのは 1 回ぶんです）"
                    : "also listed under outdated builds (selecting both frees it only once)")
        }
        return parts.joined(separator: japanese ? "・" : " · ")
    }
}

/// シミュレータ本体を、Apple の `simctl` に聞いて扱う。
///
/// 本体は `/Library/Developer/CoreSimulator` にあり、ディスクリンはそこへ直接触らない（NG2）。
/// 何が消えるかは `simctl runtime delete ... --dry-run` 自身に答えさせる。
/// 自分で選び方をまねると、Apple の判定とずれた「見せた量と実際に減る量の食い違い」が起きるため。
public enum SimulatorRuntimes {
    /// 本体ごとの共有キャッシュの置き場所。`<ホストの OS ビルド>/<版の識別子>.<ビルド>` と並ぶ。
    public static let defaultCacheRoot = "/Library/Developer/CoreSimulator/Caches/dyld"

    /// dry-run のコマンドから、消える本体と巻き込まれるものを調べる。
    ///
    /// - Returns: 調べられなければ nil（0 件とは区別する）。
    /// - Important: 引数に `--dry-run` が無いコマンドは実行しない。量を測るだけのつもりで消してしまう事故を防ぐ。
    public static func targets(
        dryRun: CommandSpec, cacheRoots: [String], timeoutSeconds: Int,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> [SimulatorRuntimeTarget]? {
        guard isDryRun(dryRun) else { return nil }
        let result = CommandRunner.run(dryRun, timeoutSeconds: timeoutSeconds)
        guard result.succeeded else { return nil }
        let wanted = parseWouldDelete(result.standardOutput + "\n" + result.standardError)
        if wanted.isEmpty { return [] }

        guard let images = installed(executable: dryRun.executable, timeoutSeconds: timeoutSeconds) else {
            return nil
        }
        let chosen = images.filter { wanted.contains($0.identifier.uppercased()) }
        // dry-run が名指ししたのに一覧に無いものがあれば、量を正しく出せない。
        guard chosen.count == wanted.count else { return nil }

        let listing = CommandRunner.run(
            CommandSpec(executable: dryRun.executable, arguments: ["simctl", "list", "-j"]),
            timeoutSeconds: timeoutSeconds)
        let losing = listing.succeeded ? devicesLosingRuntime(targets: chosen, listJSON: listing.standardOutput) : nil

        let outdated: Set<String>
        if dryRun.arguments.contains("--outdated") {
            outdated = []
        } else {
            outdated = outdatedIdentifiers(executable: dryRun.executable, timeoutSeconds: timeoutSeconds)
        }

        return chosen.map { runtime in
            SimulatorRuntimeTarget(
                runtime: runtime,
                cacheBytes: isCancelled() ? 0 : cacheBytes(for: runtime, roots: cacheRoots, isCancelled: isCancelled),
                devicesLosingRuntime: losing.map { $0[runtime.identifier] ?? 0 },
                alsoOutdated: outdated.contains(runtime.identifier.uppercased()))
        }
    }

    /// 入っている本体の一覧。`simctl runtime list -j` を読む。
    public static func installed(executable: String, timeoutSeconds: Int) -> [SimulatorRuntime]? {
        let result = CommandRunner.run(
            CommandSpec(executable: executable, arguments: ["simctl", "runtime", "list", "-j"]),
            timeoutSeconds: timeoutSeconds)
        guard result.succeeded else { return nil }
        return parseImages(result.standardOutput)
    }

    static func isDryRun(_ spec: CommandSpec) -> Bool {
        spec.arguments.contains("--dry-run") || spec.arguments.contains("-n")
    }

    /// `simctl runtime list -j` の出力を読む。読めない項目は飛ばす。
    static func parseImages(_ json: String) -> [SimulatorRuntime]? {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let formatter = ISO8601DateFormatter()
        return root.values.compactMap { value -> SimulatorRuntime? in
            guard let image = value as? [String: Any],
                let identifier = image["identifier"] as? String,
                let runtimeIdentifier = image["runtimeIdentifier"] as? String
            else { return nil }
            let size = (image["sizeBytes"] as? NSNumber)?.int64Value ?? 0
            return SimulatorRuntime(
                identifier: identifier,
                runtimeIdentifier: runtimeIdentifier,
                version: image["version"] as? String ?? "?",
                build: image["build"] as? String ?? "?",
                sizeBytes: size,
                lastUsedAt: (image["lastUsedAt"] as? String).flatMap { formatter.date(from: $0) })
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// dry-run の「Would delete ...: <UUID> ...」行から、消える本体の UUID を拾う（大文字にそろえる）。
    static func parseWouldDelete(_ output: String) -> Set<String> {
        let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found = Set<String>()
        for line in output.split(separator: "\n") where line.contains("Would delete") {
            let text = String(line)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let swiftRange = Range(match.range, in: text) {
                    found.insert(text[swiftRange].uppercased())
                }
            }
        }
        return found
    }

    /// この本体の共有キャッシュの量。ホストの OS ビルドごとにフォルダが分かれるため、すべて足す。
    static func cacheBytes(
        for runtime: SimulatorRuntime, roots: [String], isCancelled: @Sendable () -> Bool = { false }
    ) -> Int64 {
        let name = runtime.runtimeIdentifier + "." + runtime.build
        var total: Int64 = 0
        for root in roots {
            guard let hosts = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for host in hosts.sorted() {
                if isCancelled() { return total }
                let path = root + "/" + host + "/" + name
                var st = stat()
                guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
                total += DirectoryMeter.measure(path: path, isCancelled: isCancelled).bytes
            }
        }
        return total
    }

    /// 本体が消えると、同じ版の別ビルドが残らない限り、その版の端末は動かせなくなる。
    /// 数は版ごとに 1 回だけ数え、最初の対象に付ける（同じ端末を 2 回数えない）。
    static func devicesLosingRuntime(targets: [SimulatorRuntime], listJSON: String) -> [String: Int]? {
        guard let data = listJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let runtimes = root["runtimes"] as? [[String: Any]],
            let devices = root["devices"] as? [String: Any]
        else { return nil }

        let removed = Set(targets.map { $0.runtimeIdentifier + "|" + $0.build })
        let remaining = Set(
            runtimes.compactMap { entry -> String? in
                guard let identifier = entry["identifier"] as? String,
                    let build = entry["buildversion"] as? String,
                    !removed.contains(identifier + "|" + build)
                else { return nil }
                return identifier
            })

        var counts: [String: Int] = [:]
        var counted = Set<String>()
        for runtime in targets {
            guard !remaining.contains(runtime.runtimeIdentifier),
                counted.insert(runtime.runtimeIdentifier).inserted
            else { continue }
            counts[runtime.identifier] = (devices[runtime.runtimeIdentifier] as? [Any])?.count ?? 0
        }
        return counts
    }

    private static func outdatedIdentifiers(executable: String, timeoutSeconds: Int) -> Set<String> {
        let result = CommandRunner.run(
            CommandSpec(
                executable: executable, arguments: ["simctl", "runtime", "delete", "--outdated", "--dry-run"]),
            timeoutSeconds: timeoutSeconds)
        guard result.succeeded else { return [] }
        return parseWouldDelete(result.standardOutput + "\n" + result.standardError)
    }

    /// 日付だけを、その Mac の暦で出す（時刻まで出すと読みにくい）。
    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
