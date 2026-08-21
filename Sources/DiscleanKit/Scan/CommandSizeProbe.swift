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

/// `MeasureSpec` に従って対象量を測る。測れない場合は nil を返す（0 と区別する）。
public enum CommandSizeProbe {
    /// スキャン中に許す測定時間。実行時（apply）はルールの timeoutSeconds に従う。
    public static let scanTimeoutSeconds = 10

    public static func measure(
        _ spec: MeasureSpec, home: String, timeoutSeconds: Int = 20,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Int64? {
        switch spec.kind {
        case .paths:
            guard let paths = spec.paths, !paths.isEmpty else { return nil }
            return measurePaths(paths.map { Expand.tilde($0, home: home) }, isCancelled: isCancelled)

        case .commandPath:
            guard let command = spec.command else { return nil }
            let result = CommandRunner.run(command, timeoutSeconds: timeoutSeconds)
            guard result.succeeded else { return nil }
            let path =
                result.standardOutput
                .split(separator: "\n").first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard path.hasPrefix("/") || path.hasPrefix("~") else { return nil }
            return measurePaths([Expand.tilde(path, home: home)], isCancelled: isCancelled)

        case .dockerReclaimable:
            guard let command = spec.command else { return nil }
            let result = CommandRunner.run(command, timeoutSeconds: timeoutSeconds)
            guard result.succeeded else { return nil }
            return dockerReclaimable(result.standardOutput)

        case .simctlUnavailable:
            guard let command = spec.command else { return nil }
            let result = CommandRunner.run(command, timeoutSeconds: timeoutSeconds)
            guard result.succeeded else { return nil }
            let paths = unavailableSimulatorPaths(result.standardOutput, home: home)
            // 対応するデバイスが 1 つも無いなら「0 バイト」と分かっている状態。
            return measurePaths(paths, isCancelled: isCancelled)
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
