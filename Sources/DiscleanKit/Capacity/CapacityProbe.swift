import Foundation

/// 空き容量の計測 1 回分。
public struct CapacitySample: Codable, Sendable, Equatable {
    /// 即時利用可能な空き（`volumeAvailableCapacityKey`）。
    public let strictBytes: Int64?
    /// purgeable を含む空き（`volumeAvailableCapacityForImportantUsageKey`）。
    public let importantBytes: Int64?
    /// Time Machine のローカルスナップショット数。取得できなければ nil。
    public let snapshotCount: Int?
    public let at: Date

    public init(strictBytes: Int64?, importantBytes: Int64?, snapshotCount: Int?, at: Date = Date()) {
        self.strictBytes = strictBytes
        self.importantBytes = importantBytes
        self.snapshotCount = snapshotCount
        self.at = at
    }
}

/// ボリュームの空き容量とローカルスナップショットの計測。
public struct CapacityProbe: Sendable {
    private let path: String

    public init(path: String = NSHomeDirectory()) {
        self.path = path
    }

    public func sample(includeSnapshots: Bool = true) -> CapacitySample {
        var strict: Int64?
        var important: Int64?
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]) {
            if let available = values.volumeAvailableCapacity { strict = Int64(available) }
            if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
                important = Int64(importantUsage)
            }
        }
        let snapshots = includeSnapshots ? CapacityProbe.localSnapshotCount() : nil
        return CapacitySample(strictBytes: strict, importantBytes: important, snapshotCount: snapshots)
    }

    /// `tmutil listlocalsnapshots /` の行数。tmutil が無い・失敗した場合は nil。
    static func localSnapshotCount() -> Int? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/tmutil") else { return nil }
        let result = CommandRunner.run(
            CommandSpec(executable: "/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"]),
            timeoutSeconds: 5
        )
        guard result.exitCode == 0 else { return nil }
        let lines = result.standardOutput
            .split(separator: "\n")
            .filter { $0.contains("com.apple.TimeMachine") }
        return lines.count
    }
}
