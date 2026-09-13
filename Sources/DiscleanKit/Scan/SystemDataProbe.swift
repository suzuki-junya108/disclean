import Foundation

/// 「システムデータ」の中身 1 つ。**消さずに**、何で・なぜ消さないか・どう減らせるかを伝える。
public struct SystemDataItem: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case simulatorRuntimes = "simulator-runtimes"
        case swap
        case sleepImage = "sleep-image"
        case softwareUpdates = "software-updates"
        case systemLogs = "system-logs"
        case fileProvider = "file-provider"
        case userTemporary = "user-temporary"
        case purgeable
    }

    public enum State: String, Sendable {
        /// 測れた。
        case measured
        /// 読めなかった（フルディスクアクセスが無いなど）。量は分からない。
        case blocked
        /// この Mac には無い。
        case absent
        /// 聞いた先が答えなかった。量は分からない。
        case unknown
    }

    public let kind: Kind
    /// 量。分からなければ nil（0 とは区別する）。
    public let bytes: Int64?
    public let state: State
    public let places: [String]
    /// 補足の行（本体の一覧・スナップショットの数・一部読めなかった など）。
    public let details: [String]
    public let text: SystemDataText

    public init(
        kind: Kind, bytes: Int64?, state: State, places: [String], details: [String], text: SystemDataText
    ) {
        self.kind = kind
        self.bytes = bytes
        self.state = state
        self.places = places
        self.details = details
        self.text = text
    }
}

/// 1 項目ぶんの説明。安全に関わる「なぜ消さないか」を必ず持つ。
public struct SystemDataText: Sendable, Equatable {
    public let title: String
    public let whatItIs: String
    public let whyNotDeleted: String
    public let howToReduce: String
}

public struct SystemDataResult: Sendable {
    /// 大きい順。量が分からないもの・無いものは後ろ。
    public let items: [SystemDataItem]
    /// 途中でやめた。
    public let interrupted: Bool

    /// 読めなかった場所があった。
    public var blocked: Bool { items.contains { $0.state == .blocked } }
}

/// どこを測るか。テストでは一時ディレクトリに差し替える。
public struct SystemDataLocations: Sendable {
    /// 測る場所 1 つ。`excluding` の子は数えない（別の項目で数えているもの）。
    public struct Place: Sendable {
        public let path: String
        public let excluding: [String]

        public init(_ path: String, excluding: [String] = []) {
            self.path = path
            self.excluding = excluding
        }
    }

    /// `xcrun`。Xcode が無い Mac では nil にする。
    public var simctl: String?
    public var simulatorCacheRoots: [String]
    public var sleepImage: String
    public var softwareUpdates: [Place]
    public var systemLogs: [Place]
    public var fileProvider: [Place]
    public var userTemporary: [Place]
    public var swapUsedBytes: @Sendable () -> Int64?
    public var capacity: @Sendable () -> CapacitySample

    public init(
        simctl: String?, simulatorCacheRoots: [String], sleepImage: String, softwareUpdates: [Place],
        systemLogs: [Place], fileProvider: [Place], userTemporary: [Place],
        swapUsedBytes: @escaping @Sendable () -> Int64?, capacity: @escaping @Sendable () -> CapacitySample
    ) {
        self.simctl = simctl
        self.simulatorCacheRoots = simulatorCacheRoots
        self.sleepImage = sleepImage
        self.softwareUpdates = softwareUpdates
        self.systemLogs = systemLogs
        self.fileProvider = fileProvider
        self.userTemporary = userTemporary
        self.swapUsedBytes = swapUsedBytes
        self.capacity = capacity
    }

    /// この Mac の実際の場所。一覧は**コードに固定**し、配信されるルールでは広げない。
    /// ホームの外を読む入口を、遠隔から書き換えられる場所に置かないため。
    public static func live(home: String) -> SystemDataLocations {
        let temp = darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        let cache = darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR)
        let fileProviderTemp = "com.apple.fileproviderd"
        let xcrun = "/usr/bin/xcrun"
        return SystemDataLocations(
            simctl: FileManager.default.isExecutableFile(atPath: xcrun) && hasXcode() ? xcrun : nil,
            simulatorCacheRoots: [SimulatorRuntimes.defaultCacheRoot],
            sleepImage: "/private/var/vm/sleepimage",
            softwareUpdates: [Place("/Library/Updates")],
            systemLogs: [Place("/private/var/db/diagnostics"), Place("/private/var/db/uuidtext")],
            fileProvider: [Place(home + "/Library/Application Support/FileProvider")]
                + (temp.map { [Place($0 + "/" + fileProviderTemp)] } ?? []),
            userTemporary: (temp.map { [Place($0, excluding: [fileProviderTemp])] } ?? [])
                + (cache.map { [Place($0)] } ?? []),
            swapUsedBytes: swapUsed,
            capacity: { CapacityProbe(path: home).sample() })
    }

    /// `xcrun simctl` は Xcode が無いと動かない（コマンドラインツールだけでは入っていない）。
    /// 無い Mac で呼ぶと、開発ツールの導入を促す画面が出ることがあるため、先に確かめる。
    private static func hasXcode() -> Bool {
        let result = CommandRunner.run(
            CommandSpec(executable: "/usr/bin/xcode-select", arguments: ["-p"]), timeoutSeconds: 5)
        guard result.succeeded else { return false }
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasSuffix(".app/Contents/Developer")
    }

    private static func darwinUserDirectory(_ name: Int32) -> String? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: bytes, encoding: .utf8) else { return nil }
        return PathGuard.normalize(PathGuard.resolve(path))
    }

    /// `vm.swapusage` の使用中の量。
    private static let swapUsed: @Sendable () -> Int64? = {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Int64(usage.xsu_used)
    }
}

/// システムデータの中身を**読むだけ**で測る。何も消さず、何も書かない。
///
/// macOS の「システムデータ」は、ディスクリンのルールが見る場所（ホームの中）の外にも大きく広がっている。
/// 消せないものまで黙っていると「なぜ減らないのか」が分からないので、減らし方と一緒に見せる。
/// 片づけられるのは、Apple の `simctl` を通すシミュレータ本体だけ（ルール側で扱う）。
public struct SystemDataProbe: Sendable {
    private let japanese: Bool
    private let locations: SystemDataLocations
    private let commandTimeoutSeconds: Int

    public init(env: DiscleanEnvironment, locations: SystemDataLocations? = nil, commandTimeoutSeconds: Int = 20) {
        self.japanese = env.isJapanese
        self.locations = locations ?? .live(home: env.home)
        self.commandTimeoutSeconds = commandTimeoutSeconds
    }

    public func scan(
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: WorkProgressHandler = ignoreProgress
    ) async -> SystemDataResult {
        let kinds = SystemDataItem.Kind.allCases
        var items: [SystemDataItem] = []
        onProgress(WorkProgress(step: .counting, total: kinds.count))
        for kind in kinds {
            if isCancelled() { break }
            let text = SystemDataTexts.text(kind, japanese: japanese)
            onProgress(
                WorkProgress(
                    step: .measuring, ruleId: kind.rawValue, path: text.title, completed: items.count,
                    total: kinds.count))
            let item = measure(kind, text: text, isCancelled: isCancelled)
            items.append(item)
            onProgress(
                WorkProgress(
                    step: .measuring, ruleId: kind.rawValue, path: text.title, completed: items.count,
                    total: kinds.count, bytes: item.bytes ?? 0))
        }
        return SystemDataResult(items: Self.ordered(items), interrupted: isCancelled())
    }

    /// 大きい順。量が分からないもの、無いものは後ろへ回す（小さい数字と混ぜない）。
    static func ordered(_ items: [SystemDataItem]) -> [SystemDataItem] {
        func rank(_ item: SystemDataItem) -> Int {
            switch item.state {
            case .measured: 0
            case .blocked, .unknown: 1
            case .absent: 2
            }
        }
        return items.sorted { lhs, rhs in
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return (lhs.bytes ?? 0) > (rhs.bytes ?? 0)
        }
    }

    private func measure(
        _ kind: SystemDataItem.Kind, text: SystemDataText, isCancelled: @escaping @Sendable () -> Bool
    ) -> SystemDataItem {
        switch kind {
        case .simulatorRuntimes: return measureRuntimes(text: text, isCancelled: isCancelled)
        case .swap: return measureSwap(text: text)
        case .sleepImage: return measureFile(kind, path: locations.sleepImage, text: text)
        case .softwareUpdates: return measurePlaces(kind, locations.softwareUpdates, text: text, isCancelled)
        case .systemLogs: return measurePlaces(kind, locations.systemLogs, text: text, isCancelled)
        case .fileProvider: return measurePlaces(kind, locations.fileProvider, text: text, isCancelled)
        case .userTemporary: return measurePlaces(kind, locations.userTemporary, text: text, isCancelled)
        case .purgeable: return measurePurgeable(text: text)
        }
    }

    private func measureRuntimes(text: SystemDataText, isCancelled: @escaping @Sendable () -> Bool) -> SystemDataItem {
        let kind = SystemDataItem.Kind.simulatorRuntimes
        guard let simctl = locations.simctl else {
            return SystemDataItem(
                kind: kind, bytes: 0, state: .absent, places: [],
                details: [japanese ? "Xcode のシミュレータは入っていません。" : "Xcode simulators are not installed."],
                text: text)
        }
        guard let images = SimulatorRuntimes.installed(executable: simctl, timeoutSeconds: commandTimeoutSeconds)
        else {
            return SystemDataItem(
                kind: kind, bytes: nil, state: .unknown, places: [],
                details: [
                    japanese
                        ? "simctl が一覧を返しませんでした（Xcode を一度起動すると直ることがあります）。"
                        : "simctl did not return the list (launching Xcode once may fix this)."
                ],
                text: text)
        }
        if images.isEmpty {
            return SystemDataItem(kind: kind, bytes: 0, state: .absent, places: [], details: [], text: text)
        }
        var cache = DirectoryMeasurement.zero
        for root in locations.simulatorCacheRoots {
            let measured = DirectoryMeter.measure(path: root, isCancelled: isCancelled)
            cache.bytes += measured.bytes
            cache.blocked = cache.blocked || measured.blocked
        }
        var details = images.map { image -> String in
            let used =
                image.lastUsedAt.map {
                    japanese
                        ? "最後に使った日 \(SimulatorRuntimes.dayText($0))"
                        : "last used \(SimulatorRuntimes.dayText($0))"
                } ?? (japanese ? "使った記録がありません" : "no record of use")
            return "\(image.name(japanese: japanese)) \(ByteText.string(image.sizeBytes))"
                + (japanese ? "・" : " · ") + used
        }
        if cache.bytes > 0 {
            details.append(
                japanese
                    ? "共有キャッシュ \(ByteText.string(cache.bytes))"
                    : "shared caches \(ByteText.string(cache.bytes))")
        }
        let total = images.reduce(Int64(0)) { $0 + $1.sizeBytes } + cache.bytes
        return SystemDataItem(
            kind: kind, bytes: total, state: .measured, places: locations.simulatorCacheRoots, details: details,
            text: text)
    }

    private func measureSwap(text: SystemDataText) -> SystemDataItem {
        guard let used = locations.swapUsedBytes() else {
            return SystemDataItem(kind: .swap, bytes: nil, state: .unknown, places: [], details: [], text: text)
        }
        return SystemDataItem(
            kind: .swap, bytes: used, state: used > 0 ? .measured : .absent, places: [], details: [], text: text)
    }

    private func measureFile(_ kind: SystemDataItem.Kind, path: String, text: SystemDataText) -> SystemDataItem {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            let blocked = errno == EPERM || errno == EACCES
            return SystemDataItem(
                kind: kind, bytes: blocked ? nil : 0, state: blocked ? .blocked : .absent, places: [path],
                details: [], text: text)
        }
        // 見かけの長さではなく、実際にディスクを使っている量を出す。
        return SystemDataItem(
            kind: kind, bytes: Int64(st.st_blocks) * 512, state: .measured, places: [path], details: [], text: text)
    }

    private func measurePlaces(
        _ kind: SystemDataItem.Kind, _ places: [SystemDataLocations.Place], text: SystemDataText,
        _ isCancelled: @escaping @Sendable () -> Bool
    ) -> SystemDataItem {
        var bytes: Int64 = 0
        var found: [String] = []
        var blocked = false
        for place in places {
            if isCancelled() { break }
            var st = stat()
            guard lstat(place.path, &st) == 0 else {
                if errno == EPERM || errno == EACCES {
                    blocked = true
                    found.append(place.path)
                }
                continue
            }
            found.append(place.path)
            let measured = measure(place, isCancelled: isCancelled)
            bytes += measured.bytes
            blocked = blocked || measured.blocked
        }
        if found.isEmpty {
            return SystemDataItem(kind: kind, bytes: 0, state: .absent, places: [], details: [], text: text)
        }
        if blocked && bytes == 0 {
            return SystemDataItem(
                kind: kind, bytes: nil, state: .blocked, places: found,
                details: [
                    japanese
                        ? "読めませんでした（フルディスクアクセスを付けると測れます）。"
                        : "could not be read (grant Full Disk Access to measure)."
                ],
                text: text)
        }
        var details: [String] = []
        if blocked {
            details.append(
                japanese
                    ? "一部読めない場所がありました。実際はこれより多いことがあります。"
                    : "some parts could not be read; the real amount may be larger.")
        }
        return SystemDataItem(kind: kind, bytes: bytes, state: .measured, places: found, details: details, text: text)
    }

    private func measure(
        _ place: SystemDataLocations.Place, isCancelled: @escaping @Sendable () -> Bool
    ) -> DirectoryMeasurement {
        guard !place.excluding.isEmpty else {
            return DirectoryMeter.measure(path: place.path, isCancelled: isCancelled)
        }
        var total = DirectoryMeasurement.zero
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: place.path) else {
            total.blocked = true
            return total
        }
        for child in children where !place.excluding.contains(child) {
            if isCancelled() { break }
            let measured = DirectoryMeter.measure(path: place.path + "/" + child, isCancelled: isCancelled)
            total.bytes += measured.bytes
            total.fileCount += measured.fileCount
            total.blocked = total.blocked || measured.blocked
        }
        return total
    }

    private func measurePurgeable(text: SystemDataText) -> SystemDataItem {
        let sample = locations.capacity()
        var details: [String] = []
        if let snapshots = sample.snapshotCount {
            details.append(
                japanese
                    ? "Time Machine のローカルスナップショット \(snapshots) 件"
                    : "\(snapshots) Time Machine local snapshot(s)")
        }
        guard let strict = sample.strictBytes, let important = sample.importantBytes else {
            return SystemDataItem(
                kind: .purgeable, bytes: nil, state: .unknown, places: [], details: details, text: text)
        }
        let purgeable = max(0, important - strict)
        return SystemDataItem(
            kind: .purgeable, bytes: purgeable, state: purgeable > 0 ? .measured : .absent, places: [],
            details: details, text: text)
    }
}

/// 項目ごとの説明文。やさしい言葉を先に、専門語は括弧で添える。
enum SystemDataTexts {
    static func text(_ kind: SystemDataItem.Kind, japanese: Bool) -> SystemDataText {
        japanese ? ja(kind) : en(kind)
    }

    private static func ja(_ kind: SystemDataItem.Kind) -> SystemDataText {
        switch kind {
        case .simulatorRuntimes:
            SystemDataText(
                title: "シミュレータ本体（ランタイム）",
                whatItIs: "Xcode で iPhone などのシミュレータを動かすための OS 本体と、その共有キャッシュです。",
                whyNotDeleted: "ホームの外（/Library）にあるため、ディスクリンは直接は触りません。Apple の simctl を通してだけ片づけます。",
                howToReduce: "「片づける」の「古いビルドのシミュレータ本体」「しばらく使っていないシミュレータ本体」から選べます。Xcode の設定 → Components でも消せます。")
        case .swap:
            SystemDataText(
                title: "仮想メモリ（スワップ）",
                whatItIs: "メモリが足りないときに、メモリの中身を一時的にディスクへ逃がしている分です。",
                whyNotDeleted: "いま使っているメモリそのものです。消すものではありません。",
                howToReduce: "メモリを多く使うアプリを閉じるか、Mac を再起動すると減ります。")
        case .sleepImage:
            SystemDataText(
                title: "スリープ用の退避ファイル（sleepimage）",
                whatItIs: "スリープ中にメモリの中身を保存しておくファイルです。",
                whyNotDeleted: "macOS がスリープのために使います。消しても次のスリープで作り直されます。",
                howToReduce: "減らすことはおすすめしません。電池が切れたときに作業中のデータを守るためのものです。")
        case .softwareUpdates:
            SystemDataText(
                title: "ダウンロード済みの macOS アップデート",
                whatItIs: "まだ適用していない、ダウンロード済みのアップデートです。",
                whyNotDeleted: "管理者だけが触れる場所にあり、途中で消すとアップデートが壊れることがあります。",
                howToReduce: "システム設定 → 一般 → ソフトウェアアップデートで適用すると、不要になった分が消えます。")
        case .systemLogs:
            SystemDataText(
                title: "システムの記録（ログ）",
                whatItIs: "macOS が動作を記録しているログです。",
                whyNotDeleted: "macOS が古いものから自動で消します。消すと、不具合が起きたときに原因を調べられなくなります。",
                howToReduce: "手で減らす必要はありません。")
        case .fileProvider:
            SystemDataText(
                title: "iCloud Drive などの同期の作業領域",
                whatItIs: "iCloud Drive・Google ドライブ・Dropbox などが、同期のために手元に置いているデータです。",
                whyNotDeleted: "同期中のデータを直接消すと、同期が壊れたり、ファイルを失ったりします。",
                howToReduce: "Finder で大きなフォルダを右クリックし「ダウンロードを削除」を選ぶと、クラウドに残したまま手元から外せます。")
        case .userTemporary:
            SystemDataText(
                title: "アプリの一時置き場",
                whatItIs: "アプリが作業中に使う一時ファイルとキャッシュです（/private/var/folders）。",
                whyNotDeleted: "起動中のアプリが使っていることがあります。macOS が再起動のときなどに自動で片づけます。",
                howToReduce: "Mac を再起動すると、使われていない分が片づきます。")
        case .purgeable:
            SystemDataText(
                title: "空きが足りなくなると自動で空く領域（purgeable）",
                whatItIs: "macOS が「空きが足りなくなったら消してよい」として取ってあるデータです。Time Machine のローカルスナップショットや、iCloud の手元のコピーなどが含まれます。",
                whyNotDeleted: "macOS が必要になったときに自分で解放します。",
                howToReduce: "何もしなくて大丈夫です。すぐに空けたいときは、Time Machine のバックアップを最後まで済ませると古いスナップショットが消えます。")
        }
    }

    private static func en(_ kind: SystemDataItem.Kind) -> SystemDataText {
        switch kind {
        case .simulatorRuntimes:
            SystemDataText(
                title: "Simulator runtimes",
                whatItIs: "The OS images Xcode uses to run iPhone and other simulators, plus their shared caches.",
                whyNotDeleted: "They live outside your home (/Library), so disclean never touches them directly; "
                    + "it only asks Apple's simctl.",
                howToReduce: "Select \"Outdated simulator runtimes\" or \"Unused simulator runtimes\" "
                    + "in the clean list, or use Xcode Settings → Components.")
        case .swap:
            SystemDataText(
                title: "Virtual memory (swap)",
                whatItIs: "Memory contents moved to disk while RAM is short.",
                whyNotDeleted: "It is memory in use right now, not something to delete.",
                howToReduce: "Quit memory-hungry apps or restart the Mac.")
        case .sleepImage:
            SystemDataText(
                title: "Sleep image (sleepimage)",
                whatItIs: "The file that stores memory contents while the Mac sleeps.",
                whyNotDeleted: "macOS uses it for sleep and recreates it on the next sleep.",
                howToReduce: "Not recommended; it protects unsaved work when the battery runs out.")
        case .softwareUpdates:
            SystemDataText(
                title: "Downloaded macOS updates",
                whatItIs: "Updates that were downloaded but not installed yet.",
                whyNotDeleted: "They are in an admin-only location, and removing them mid-way can break the update.",
                howToReduce: "Install them from System Settings → General → Software Update.")
        case .systemLogs:
            SystemDataText(
                title: "System logs",
                whatItIs: "Logs macOS keeps about what the system did.",
                whyNotDeleted: "macOS removes old ones on its own; "
                    + "deleting them makes problems impossible to diagnose.",
                howToReduce: "No action needed.")
        case .fileProvider:
            SystemDataText(
                title: "iCloud Drive and other sync staging",
                whatItIs: "Data kept locally by iCloud Drive, Google Drive, Dropbox and similar apps while syncing.",
                whyNotDeleted: "Deleting sync data directly can break syncing or lose files.",
                howToReduce: "In Finder, right-click a large folder and choose \"Remove Download\" "
                    + "to keep it only in the cloud.")
        case .userTemporary:
            SystemDataText(
                title: "App temporary files",
                whatItIs: "Temporary files and caches apps use while running (/private/var/folders).",
                whyNotDeleted: "Running apps may be using them; macOS cleans them up itself, e.g. on restart.",
                howToReduce: "Restarting the Mac clears what is no longer used.")
        case .purgeable:
            SystemDataText(
                title: "Space macOS frees on demand (purgeable)",
                whatItIs: "Data macOS keeps but may remove when space runs low, "
                    + "such as Time Machine local snapshots and local iCloud copies.",
                whyNotDeleted: "macOS releases it by itself when space is needed.",
                howToReduce: "No action needed. Finishing a Time Machine backup removes older snapshots.")
        }
    }
}
