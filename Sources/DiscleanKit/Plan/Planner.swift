import Foundation

/// 実行計画。Tier A を既定選択、Tier B は明示選択、Tier C は選択不可。
public struct Plan: Sendable {
    public let runId: String
    public let createdAt: Date
    public let selected: [ScanItem]

    public var totalBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }
    public var hasIrreversible: Bool { selected.contains { !$0.undoable } }
}

public enum PlannerError: Error, Equatable {
    case unknownRuleId(String)
    case tierCSelected(String)
}

public struct Planner: Sendable {
    public init() {}

    public func plan(
        from result: ScanResult,
        tiers: Set<Tier> = [.a],
        select: [String] = [],
        deselect: [String] = [],
        now: Date = Date()
    ) throws -> Plan {
        let byId = Dictionary(uniqueKeysWithValues: result.items.map { ($0.ruleId, $0) })
        for id in select + deselect {
            guard let item = byId[id] else { throw PlannerError.unknownRuleId(id) }
            if item.tier == .c { throw PlannerError.tierCSelected(id) }
        }
        if tiers.contains(.c) { throw PlannerError.tierCSelected("tier-c") }

        var chosen = result.readyItems.filter { tiers.contains($0.tier) }
        for id in select where !chosen.contains(where: { $0.ruleId == id }) {
            if let item = byId[id], item.state == .ready { chosen.append(item) }
        }
        chosen.removeAll { deselect.contains($0.ruleId) }
        chosen.sort { $0.bytes > $1.bytes }
        return Plan(runId: ULID.generate(now: now), createdAt: now, selected: chosen)
    }
}

/// 時刻順にソートできる 26 文字の識別子。
public enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate(now: Date = Date()) -> String {
        var timestamp = UInt64(now.timeIntervalSince1970 * 1000)
        var chars = [Character](repeating: "0", count: 26)
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = alphabet[Int(timestamp % 32)]
            timestamp /= 32
        }
        for i in 10..<26 {
            chars[i] = alphabet[Int.random(in: 0..<32)]
        }
        return String(chars)
    }
}
