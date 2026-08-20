import Foundation

/// 2 つのルール集合を突き合わせ、拡大・縮小・中立に分類する。
public enum CatalogDiffer {
    public static func diff(current: [Rule], next: [Rule], revocations: [String] = []) -> CatalogDiff {
        var diff = CatalogDiff()
        let currentById = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let nextById = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })

        func add(_ entry: DiffEntry) {
            if entry.change.isNeutral {
                diff.neutral.append(entry)
            } else if entry.change.isExpanding {
                diff.expanding.append(entry)
            } else {
                diff.shrinking.append(entry)
            }
        }

        for id in revocations where currentById[id] != nil {
            add(DiffEntry(ruleId: id, change: .revoked, before: "enabled", after: "revoked", newPaths: []))
        }

        for (id, newRule) in nextById.sorted(by: { $0.key < $1.key }) {
            guard let old = currentById[id] else {
                add(
                    DiffEntry(
                        ruleId: id, change: .ruleAdded, before: nil, after: newRule.tier.rawValue,
                        newPaths: newRule.paths ?? []))
                continue
            }
            compare(old: old, next: newRule, add: add)
        }

        for (id, old) in currentById.sorted(by: { $0.key < $1.key }) where nextById[id] == nil {
            add(DiffEntry(ruleId: id, change: .ruleRemoved, before: old.tier.rawValue, after: nil, newPaths: []))
        }
        return diff
    }

    /// 同一 id のルール同士を比べ、変化を 1 件ずつ分類して渡す。
    private static func compare(old: Rule, next: Rule, add: (DiffEntry) -> Void) {
        let id = old.id
        let oldPaths = Set(old.paths ?? [])
        let newPaths = Set(next.paths ?? [])
        let added = newPaths.subtracting(oldPaths).sorted()
        let removed = oldPaths.subtracting(newPaths).sorted()
        if !added.isEmpty {
            add(
                DiffEntry(
                    ruleId: id, change: .pathAdded, before: nil, after: added.joined(separator: ", "),
                    newPaths: added))
        }
        if !removed.isEmpty {
            add(
                DiffEntry(
                    ruleId: id, change: .pathRemoved, before: removed.joined(separator: ", "),
                    after: nil, newPaths: []))
        }
        if old.tier != next.tier {
            let raised = tierRank(next.tier) > tierRank(old.tier)
            add(
                DiffEntry(
                    ruleId: id, change: raised ? .tierRaised : .tierLowered,
                    before: old.tier.rawValue, after: next.tier.rawValue,
                    newPaths: raised ? (next.paths ?? []) : []))
        }
        if old.command != next.command {
            add(
                DiffEntry(
                    ruleId: id, change: .commandChanged,
                    before: describe(old.command), after: describe(next.command), newPaths: []))
        }
        if old.minAgeDays != next.minAgeDays {
            let relaxed = (next.minAgeDays ?? 0) < (old.minAgeDays ?? 0)
            add(
                DiffEntry(
                    ruleId: id, change: relaxed ? .ageRelaxed : .ageTightened,
                    before: old.minAgeDays.map(String.init), after: next.minAgeDays.map(String.init),
                    newPaths: []))
        }
        if old.minMacOS != next.minMacOS || old.maxMacOS != next.maxMacOS {
            let widened = isWidened(old: old, next: next)
            add(
                DiffEntry(
                    ruleId: id, change: widened ? .osScopeWidened : .osScopeNarrowed,
                    before: "\(old.minMacOS ?? "-")...\(old.maxMacOS ?? "-")",
                    after: "\(next.minMacOS ?? "-")...\(next.maxMacOS ?? "-")",
                    newPaths: widened ? (next.paths ?? []) : []))
        }
        if old.enabled != next.enabled {
            add(
                DiffEntry(
                    ruleId: id, change: next.enabled ? .ruleAdded : .ruleRemoved,
                    before: "\(old.enabled)", after: "\(next.enabled)",
                    newPaths: next.enabled ? (next.paths ?? []) : []))
        }
        if old.title != next.title || old.titleJa != next.titleJa
            || old.whatIsLost != next.whatIsLost || old.whatIsLostJa != next.whatIsLostJa
            || old.manualSteps != next.manualSteps || old.verifiedOn != next.verifiedOn
        {
            add(DiffEntry(ruleId: id, change: .textChanged, before: nil, after: nil, newPaths: []))
        }
    }

    /// OS 条件が緩くなった（= 有効になる環境が増えた）か。
    private static func isWidened(old: Rule, next: Rule) -> Bool {
        let oldMin = old.minMacOS.flatMap(SemanticVersion.init)
        let newMin = next.minMacOS.flatMap(SemanticVersion.init)
        if newMin == nil && oldMin != nil { return true }
        if let oldMin, let newMin, newMin < oldMin { return true }
        let oldMax = old.maxMacOS.flatMap(SemanticVersion.init)
        let newMax = next.maxMacOS.flatMap(SemanticVersion.init)
        if newMax == nil && oldMax != nil { return true }
        if let oldMax, let newMax, oldMax < newMax { return true }
        return false
    }

    private static func tierRank(_ tier: Tier) -> Int {
        switch tier {
        case .c: 0
        case .b: 1
        case .a: 2
        }
    }

    private static func describe(_ spec: CommandSpec?) -> String? {
        guard let spec else { return nil }
        return ([spec.executable] + spec.arguments).joined(separator: " ")
    }
}
