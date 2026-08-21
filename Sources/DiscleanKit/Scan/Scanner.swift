import AppKit
import Foundation

/// スキャン結果 1 件の状態。
public enum ItemState: String, Codable, Sendable {
    case ready
    case blocked
    case skipped
}

/// スキャン結果 1 件。
public struct ScanItem: Codable, Sendable, Equatable {
    public let ruleId: String
    public let tier: Tier
    public let title: String
    public let bytes: Int64
    public let fileCount: Int
    public let paths: [String]
    public let state: ItemState
    public let reason: String?
    public let dataless: Bool
    public let cacheHit: Bool
    public let whatIsLost: String
    public let manualSteps: String?
    public let kind: RuleKind
    public let undoable: Bool
    /// 量が測れているか。false のときは「不明」であって「0 バイト」ではない。
    public let sizeKnown: Bool
}

/// スキャン全体の結果。
public struct ScanResult: Sendable {
    public let items: [ScanItem]
    public let capacity: CapacitySample
    public let errors: [CatalogError]
    public let interrupted: Bool

    public var totalBytes: Int64 { items.filter { $0.state == .ready }.reduce(0) { $0 + $1.bytes } }
    public var readyItems: [ScanItem] { items.filter { $0.state == .ready } }
    public var hasBlocked: Bool { items.contains { $0.state == .blocked } }
}

/// 読み取り専用のスキャン。ファイルシステムへの書き込みはスキャンキャッシュのみ。
public struct Scanner: Sendable {
    private let env: DiscleanEnvironment
    private let config: Config
    private let guardian: PathGuard

    public init(env: DiscleanEnvironment, config: Config) {
        self.env = env
        self.config = config
        self.guardian = PathGuard(
            home: env.home, stateDir: env.stateDir, configDir: env.configDir, excludedPaths: config.excludedPaths)
    }

    public func scan(
        catalog: RuleCatalog,
        tiers: Set<Tier> = [.a, .b],
        ruleIds: Set<String> = [],
        useCache: Bool = true,
        isCancelled: @Sendable @escaping () -> Bool = { false }
    ) async -> ScanResult {
        DatalessPolicy.disableMaterialization()
        let cachePath = env.cacheDir + "/scan-cache.json"
        var cache = useCache ? ScanCache.load(path: cachePath) : ScanCache()

        let targets = catalog.entries.filter { entry in
            (ruleIds.isEmpty ? tiers.contains(entry.rule.tier) : ruleIds.contains(entry.rule.id))
        }

        var items: [ScanItem] = []
        var cacheUpdates: [CacheUpdate] = []

        await withTaskGroup(of: MeasureOutput.self) { group in
            var launched = 0
            let limit = max(1, config.concurrency)
            var iterator = targets.enumerated().makeIterator()

            func addNext(_ group: inout TaskGroup<MeasureOutput>) -> Bool {
                guard let (index, entry) = iterator.next() else { return false }
                let cacheSnapshot = cache
                group.addTask {
                    let input = MeasureInput(
                        entry: entry, env: env, config: config, guardian: guardian,
                        cache: useCache ? cacheSnapshot : ScanCache())
                    let measured = Self.measure(input, isCancelled: isCancelled)
                    return MeasureOutput(index: index, item: measured.item, cacheUpdates: measured.cacheUpdates)
                }
                return true
            }

            while launched < limit, addNext(&group) { launched += 1 }
            var collected: [MeasureOutput] = []
            while let output = await group.next() {
                collected.append(output)
                cacheUpdates.append(contentsOf: output.cacheUpdates)
                _ = addNext(&group)
            }
            items = collected.sorted { $0.index < $1.index }.map(\.item)
        }

        if useCache {
            for update in cacheUpdates {
                cache.store(path: update.path, bytes: update.bytes, fileCount: update.fileCount)
            }
            cache.save(path: cachePath)
        }

        // Tier 別・サイズ降順に整える。
        let tierOrder: [Tier] = [.a, .b, .c]
        let sorted = items.sorted { lhs, rhs in
            let l = tierOrder.firstIndex(of: lhs.tier) ?? 9
            let r = tierOrder.firstIndex(of: rhs.tier) ?? 9
            if l != r { return l < r }
            return lhs.bytes > rhs.bytes
        }
        return ScanResult(
            items: sorted,
            capacity: CapacityProbe(path: env.home).sample(),
            errors: catalog.errors,
            interrupted: isCancelled()
        )
    }

    private static func measure(
        _ input: MeasureInput, isCancelled: @Sendable () -> Bool
    ) -> MeasuredItem {
        let rule = input.entry.rule
        let japanese = input.env.isJapanese

        // command 型: ツールの有無だけを確かめる。回収量は実行してみるまで分からない。
        if rule.kind == .command {
            return MeasuredItem(
                item: measureCommandRule(
                    rule, env: input.env, japanese: japanese, isCancelled: isCancelled),
                cacheUpdates: [])
        }
        return measureDirectoryRule(input, isCancelled: isCancelled)
    }

    private static func measureCommandRule(
        _ rule: Rule, env: DiscleanEnvironment, japanese: Bool, isCancelled: @Sendable () -> Bool
    ) -> ScanItem {
        if let detect = rule.detect {
            let result = CommandRunner.run(detect, timeoutSeconds: 5)
            guard result.succeeded else {
                let reason = result.exitCode == 127 ? "tool-not-found" : "daemon-not-running"
                return makeItem(
                    rule: rule, japanese: japanese, measurement: PathMeasurement(),
                    state: .skipped, reason: reason)
            }
        }

        // 実行前に量を測る。測れないルールだけが「実行してみるまで不明」になる。
        // スキャン中の測定には上限を置く。遅いツール 1 つでスキャン全体を止めない。
        // 測れなければ「不明」として扱い、0 バイトとは区別する。
        guard let spec = rule.measure,
            let bytes = CommandSizeProbe.measure(
                spec, home: env.home, timeoutSeconds: CommandSizeProbe.scanTimeoutSeconds,
                isCancelled: isCancelled)
        else {
            return makeItem(
                rule: rule, japanese: japanese, measurement: PathMeasurement(),
                state: .ready, reason: nil, sizeKnown: false)
        }
        var measurement = PathMeasurement()
        measurement.bytes = bytes
        // 空なら実行する意味がない。理由を付けて外す。
        if bytes == 0 {
            return makeItem(
                rule: rule, japanese: japanese, measurement: measurement, state: .skipped, reason: "empty")
        }
        return makeItem(rule: rule, japanese: japanese, measurement: measurement, state: .ready, reason: nil)
    }

    private static func measureDirectoryRule(
        _ input: MeasureInput, isCancelled: @Sendable () -> Bool
    ) -> MeasuredItem {
        let rule = input.entry.rule
        let japanese = input.env.isJapanese

        // 起動中のアプリのデータは実行時に必ず見送られる。候補として数えない。
        if let running = runningApp(in: rule.requiresQuitApps ?? []) {
            return MeasuredItem(
                item: makeItem(
                    rule: rule, japanese: japanese, measurement: PathMeasurement(),
                    state: .skipped, reason: "app-running:\(running)"),
                cacheUpdates: [])
        }

        var measurement = PathMeasurement()
        var blocked = false
        var cacheUpdates: [CacheUpdate] = []

        for rawPath in rule.paths ?? [] {
            if isCancelled() { break }
            let path = PathGuard.normalize(Expand.tilde(rawPath, home: input.env.home))
            var st = stat()
            guard lstat(path, &st) == 0 else {
                if errno == EPERM || errno == EACCES { blocked = true }
                continue
            }
            measurement.paths.append(path)

            // 最終更新からの日数で対象を絞るルールは、絞った後だけを数える。
            // 全体を数えると、表示より実際に移る量が少なくなる。
            if let minAgeDays = rule.minAgeDays {
                let aged = measureAged(
                    path: path, minAgeDays: minAgeDays, now: Date(), isCancelled: isCancelled)
                measurement.bytes += aged.bytes
                measurement.fileCount += aged.fileCount
                measurement.dataless = measurement.dataless || aged.dataless
                blocked = blocked || aged.blocked
                continue
            }

            if let cached = input.cache.lookup(path: path) {
                measurement.bytes += cached.bytes
                measurement.fileCount += cached.fileCount
                measurement.cacheHit = true
                continue
            }
            let measured = DirectoryMeter.measure(path: path, isCancelled: isCancelled)
            measurement.bytes += measured.bytes
            measurement.fileCount += measured.fileCount
            measurement.dataless = measurement.dataless || measured.dataless
            blocked = blocked || measured.blocked
            cacheUpdates.append(
                CacheUpdate(path: path, bytes: measured.bytes, fileCount: measured.fileCount))
        }

        let state = directoryState(rule: rule, measurement: measurement, blocked: blocked)
        return MeasuredItem(
            item: makeItem(
                rule: rule, japanese: japanese, measurement: measurement,
                state: state.state, reason: state.reason),
            cacheUpdates: cacheUpdates)
    }

    /// 直下の項目のうち、最終更新から `minAgeDays` 以上たったものだけを測る。
    /// 実行時（Executor）の判定と同じ基準にして、表示と実際の差をなくす。
    private static func measureAged(
        path: String, minAgeDays: Int, now: Date, isCancelled: @Sendable () -> Bool
    ) -> DirectoryMeasurement {
        var total = DirectoryMeasurement.zero
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            var st = stat()
            if lstat(path, &st) != 0, errno == EPERM || errno == EACCES { total.blocked = true }
            return total
        }
        for child in children {
            if isCancelled() { break }
            let childPath = path + "/" + child
            var st = stat()
            guard lstat(childPath, &st) == 0 else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            guard now.timeIntervalSince(modified) / 86_400 >= Double(minAgeDays) else { continue }
            let measured = DirectoryMeter.measure(path: childPath, isCancelled: isCancelled)
            total.bytes += measured.bytes
            total.fileCount += measured.fileCount
            total.dataless = total.dataless || measured.dataless
            total.blocked = total.blocked || measured.blocked
        }
        return total
    }

    /// `requiresQuitApps` のアプリが起動しているか。
    private static func runningApp(in bundleIds: [String]) -> String? {
        guard !bundleIds.isEmpty else { return nil }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return bundleIds.first { running.contains($0) }
    }

    /// 測定結果から項目の状態を決める。「消せる」以外は必ず理由を持たせる。
    private static func directoryState(
        rule: Rule, measurement: PathMeasurement, blocked: Bool
    ) -> (state: ItemState, reason: String?) {
        if measurement.paths.isEmpty { return (.skipped, "not-found") }
        if blocked && measurement.bytes == 0 { return (.blocked, "permission-denied") }
        if rule.kind == .directory && measurement.bytes == 0 { return (.skipped, "empty") }
        // Tier C は提示のみ。選べないため ready にしない。
        if rule.tier == .c { return (.skipped, "report-only") }
        return (.ready, nil)
    }

    private static func makeItem(
        rule: Rule, japanese: Bool, measurement: PathMeasurement, state: ItemState, reason: String?,
        sizeKnown: Bool = true
    ) -> ScanItem {
        ScanItem(
            ruleId: rule.id, tier: rule.tier, title: rule.displayTitle(japanese: japanese),
            bytes: measurement.bytes, fileCount: measurement.fileCount, paths: measurement.paths,
            state: state, reason: reason, dataless: measurement.dataless, cacheHit: measurement.cacheHit,
            whatIsLost: rule.displayWhatIsLost(japanese: japanese), manualSteps: rule.manualSteps,
            kind: rule.kind, undoable: rule.kind == .directory, sizeKnown: sizeKnown)
    }
}

/// 1 ルール分の測定値。
private struct PathMeasurement: Sendable {
    var bytes: Int64 = 0
    var fileCount = 0
    var paths: [String] = []
    var dataless = false
    var cacheHit = false
}

/// 1 ルールを測るための入力一式。
private struct MeasureInput: Sendable {
    let entry: CatalogEntry
    let env: DiscleanEnvironment
    let config: Config
    let guardian: PathGuard
    let cache: ScanCache
}

/// 測定結果とキャッシュ更新分。
private struct MeasuredItem: Sendable {
    let item: ScanItem
    let cacheUpdates: [CacheUpdate]
}

/// 並列実行の結果を元の並び順に戻すための包み。
private struct MeasureOutput: Sendable {
    let index: Int
    let item: ScanItem
    let cacheUpdates: [CacheUpdate]
}

/// スキャンキャッシュへの書き込み 1 件。
struct CacheUpdate: Sendable {
    let path: String
    let bytes: Int64
    let fileCount: Int
}
