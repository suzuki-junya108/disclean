import Foundation
import DiscleanKit

/// TTY 判定と NO_COLOR に従う色付け、および共通の整形。
struct Output: Sendable {
    let colorEnabled: Bool
    let japanese: Bool

    init(env: DiscleanEnvironment) {
        self.colorEnabled = isatty(STDOUT_FILENO) == 1 && !env.noColor
        self.japanese = env.isJapanese
    }

    enum Style: String {
        case red = "\u{001B}[0;31m"
        case green = "\u{001B}[0;32m"
        case yellow = "\u{001B}[1;33m"
        case cyan = "\u{001B}[0;36m"
        case dim = "\u{001B}[2m"
        case bold = "\u{001B}[1m"
    }

    func styled(_ text: String, _ style: Style) -> String {
        colorEnabled ? style.rawValue + text + "\u{001B}[0m" : text
    }

    func print(_ text: String = "") {
        Swift.print(text)
    }

    func warn(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// 1000 進のバイト表記（JSON には常に整数バイトを出す）。
    static func bytes(_ value: Int64) -> String {
        if value == 0 { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: value)
    }

    static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: value)
    }

    func tierLabel(_ tier: Tier) -> String {
        switch tier {
        case .a: japanese ? "A" : "A"
        case .b: japanese ? "B" : "B"
        case .c: japanese ? "見るだけ" : "look only"
        }
    }

    func divider() {
        print(styled(String(repeating: "─", count: 46), .cyan))
    }
}

/// nil を JSON の null に落とす（異種辞書リテラルの型推論を助ける）。
func jsonOrNull(_ value: Any?) -> Any { value ?? NSNull() }

/// `--json` 出力の共通ラッパ。stdout に 1 オブジェクトだけ書く。
enum JSONOut {
    static func emit(_ object: [String: Any]) {
        var payload = object
        payload["schemaVersion"] = 1
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]),
            let text = String(data: data, encoding: .utf8)
        else {
            print("{\"schemaVersion\":1,\"errors\":[{\"reason\":\"encoding-failed\"}]}")
            return
        }
        print(text)
    }

    static func item(_ item: ScanItem) -> [String: Any] {
        var dict: [String: Any] = [
            "ruleId": item.ruleId,
            "tier": item.tier.rawValue,
            "title": item.title,
            "bytes": item.bytes,
            "fileCount": item.fileCount,
            "paths": item.paths,
            "state": item.state.rawValue,
            "dataless": item.dataless,
            "cacheHit": item.cacheHit,
            "undoable": item.undoable,
            "whatIsLost": item.whatIsLost,
        ]
        if let reason = item.reason { dict["reason"] = reason }
        if let manual = item.manualSteps { dict["manualSteps"] = manual }
        return dict
    }

    static func capacity(_ sample: CapacitySample) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["strictBytes"] = jsonOrNull(sample.strictBytes)
        dict["importantBytes"] = jsonOrNull(sample.importantBytes)
        dict["snapshotCount"] = jsonOrNull(sample.snapshotCount)
        return dict
    }
}
