import Foundation

/// 外部ツールに任せる項目（`command` 型）の対象量を測る方法。
///
/// これが無いと「実行してみるまで分からない」としか言えず、利用者は実行前に判断できない。
/// 実行の前後で同じ方法で測り、その差を「実際に空けた量」として報告する。
public struct MeasureSpec: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// 決め打ちのパスを測る。
        case paths
        /// コマンドの標準出力をパスとして扱い、そのディレクトリを測る（例 `brew --cache`）。
        case commandPath
        /// `docker system df` が報告する「回収可能」量を読む。
        case dockerReclaimable
        /// 現在の Xcode が対応しないシミュレータのデバイスだけを測る。
        case simctlUnavailable
        /// `simctl runtime delete ... --dry-run` が挙げたシミュレータ本体と、その共有キャッシュを測る。
        /// `command` は必ず dry-run にする（`--dry-run` が無ければ測らない）。`paths` は共有キャッシュの置き場所。
        case simctlRuntimes
    }

    public let kind: Kind
    public let paths: [String]?
    public let command: CommandSpec?

    public init(kind: Kind, paths: [String]? = nil, command: CommandSpec? = nil) {
        self.kind = kind
        self.paths = paths
        self.command = command
    }
}

/// 測った結果。量に加えて、消す前に読ませたい補足と、対象の場所を持つ。
public struct CommandMeasurement: Sendable, Equatable {
    public let bytes: Int64
    /// 何が消えるのかを 1 件 1 行で（例: シミュレータ本体の名前と最後に使った日）。
    public let details: [String]
    /// 実在する対象の場所（中身を見せられる場合だけ）。
    public let paths: [String]

    public init(bytes: Int64, details: [String] = [], paths: [String] = []) {
        self.bytes = bytes
        self.details = details
        self.paths = paths
    }
}

/// `MeasureSpec` に従って対象量を測る。測れない場合は nil を返す（0 と区別する）。
public enum CommandSizeProbe {
    /// スキャン中に許す測定時間。実行時（apply）はルールの timeoutSeconds に従う。
    public static let scanTimeoutSeconds = 10

    public static func measure(
        _ spec: MeasureSpec, home: String, timeoutSeconds: Int = 20,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Int64? {
        measureDetailed(
            spec, home: home, japanese: false, timeoutSeconds: timeoutSeconds, isCancelled: isCancelled)?.bytes
    }

    public static func measureDetailed(
        _ spec: MeasureSpec, home: String, japanese: Bool, timeoutSeconds: Int = 20,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> CommandMeasurement? {
        switch spec.kind {
        case .paths:
            guard let paths = spec.paths, !paths.isEmpty else { return nil }
            let expanded = paths.map { Expand.tilde($0, home: home) }
            var st = stat()
            return CommandMeasurement(
                bytes: measurePaths(expanded, isCancelled: isCancelled),
                paths: expanded.filter { lstat($0, &st) == 0 })

        case .commandPath:
            guard let command = spec.command else { return nil }
            let result = CommandRunner.run(command, timeoutSeconds: timeoutSeconds)
            guard result.succeeded else { return nil }
            let path =
                result.standardOutput
                .split(separator: "\n").first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard path.hasPrefix("/") || path.hasPrefix("~") else { return nil }
            return CommandMeasurement(
                bytes: measurePaths([Expand.tilde(path, home: home)], isCancelled: isCancelled))

        case .dockerReclaimable:
            guard let command = spec.command else { return nil }
            let result = CommandRunner.run(command, timeoutSeconds: timeoutSeconds)
            guard result.succeeded else { return nil }
            return dockerReclaimable(result.standardOutput).map { CommandMeasurement(bytes: $0) }

        case .simctlUnavailable:
            guard let command = spec.command else { return nil }
            let result = CommandRunner.run(command, timeoutSeconds: timeoutSeconds)
            guard result.succeeded else { return nil }
            let paths = unavailableSimulatorPaths(result.standardOutput, home: home)
            // 対応するデバイスが 1 つも無いなら「0 バイト」と分かっている状態。
            return CommandMeasurement(bytes: measurePaths(paths, isCancelled: isCancelled))

        case .simctlRuntimes:
            guard let command = spec.command,
                let targets = SimulatorRuntimes.targets(
                    dryRun: command, cacheRoots: spec.paths ?? [SimulatorRuntimes.defaultCacheRoot],
                    timeoutSeconds: timeoutSeconds, isCancelled: isCancelled)
            else { return nil }
            // 実測では、本体を 1 つ消すと本体の量と共有キャッシュの量の合計だけ空きが増えた。
            return CommandMeasurement(
                bytes: targets.reduce(0) { $0 + $1.totalBytes },
                details: targets.map { $0.describe(japanese: japanese) })
        }
    }

    private static func measurePaths(_ paths: [String], isCancelled: @Sendable () -> Bool) -> Int64 {
        var total: Int64 = 0
        for path in paths {
            if isCancelled() { break }
            total += DirectoryMeter.measure(path: path, isCancelled: isCancelled).bytes
        }
        return total
    }

    /// `docker system df --format {{json .}}` の各行から Reclaimable を合算する。
    static func dockerReclaimable(_ output: String) -> Int64? {
        var total: Int64 = 0
        var sawAny = false
        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let reclaimable = object["Reclaimable"] as? String
            else { continue }
            sawAny = true
            total += parseHumanSize(reclaimable) ?? 0
        }
        return sawAny ? total : nil
    }

    /// "1.234GB (80%)" のような表記をバイト数にする。
    static func parseHumanSize(_ text: String) -> Int64? {
        let trimmed = text.split(separator: "(").first.map(String.init) ?? text
        let scanner = trimmed.trimmingCharacters(in: .whitespaces)
        let number = scanner.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(number) else { return nil }
        let unit = scanner.dropFirst(number.count).trimmingCharacters(in: .whitespaces).uppercased()
        let multiplier: Double
        switch unit {
        case "B", "": multiplier = 1
        case "KB", "K": multiplier = 1_000
        case "MB", "M": multiplier = 1_000_000
        case "GB", "G": multiplier = 1_000_000_000
        case "TB", "T": multiplier = 1_000_000_000_000
        case "KIB": multiplier = 1_024
        case "MIB": multiplier = 1_048_576
        case "GIB": multiplier = 1_073_741_824
        default: return nil
        }
        return Int64(value * multiplier)
    }

    /// `simctl list devices --json` から、対応ランタイムが無いデバイスのディレクトリを拾う。
    static func unavailableSimulatorPaths(_ json: String, home: String) -> [String] {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = root["devices"] as? [String: Any]
        else { return [] }

        var paths: [String] = []
        for (_, value) in devices {
            guard let list = value as? [[String: Any]] else { continue }
            for device in list {
                let available = device["isAvailable"] as? Bool ?? true
                guard !available else { continue }
                if let dataPath = device["dataPath"] as? String {
                    // dataPath は <device>/data を指すため、デバイスごと測る。
                    paths.append((dataPath as NSString).deletingLastPathComponent)
                } else if let udid = device["udid"] as? String {
                    paths.append(home + "/Library/Developer/CoreSimulator/Devices/" + udid)
                }
            }
        }
        return paths
    }
}
