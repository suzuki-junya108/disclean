import Foundation

/// 隔離された項目 1 件。
public struct QuarantineEntry: Codable, Sendable, Equatable {
    public let ruleId: String
    public let originalPath: String
    public let quarantineRelativePath: String
    public let bytes: Int64
    public let isDirectory: Bool
    public let movedAt: Date
}

/// 隔離 1 回分。
public struct QuarantineRun: Codable, Sendable, Equatable {
    public let runId: String
    public let createdAt: Date
    public var expiresAt: Date
    public var entries: [QuarantineEntry]

    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
}

/// 隔離庫の索引。
public struct QuarantineIndex: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var runs: [QuarantineRun] = []
}

public enum QuarantineError: Error, Equatable {
    case inconsistent(String)
    case unknownRun(String)
    case cannotCreate(String)
}

/// 隔離庫（`$DISCLEAN_STATE_DIR/quarantine/`）の読み書き。
/// 実削除を行うのはこの型の `purge` だけ。
public struct QuarantineStore: Sendable {
    public let root: String
    private var indexPath: String { root + "/index.json" }

    public init(root: String) {
        self.root = root
    }

    public func loadIndex() -> QuarantineIndex {
        let index = (try? JSONIO.read(QuarantineIndex.self, at: indexPath)) ?? QuarantineIndex()
        return healed(index)
    }

    /// 古い版が 0 バイトと記録した項目を、実体を測り直して直す。
    /// 記録が壊れていると、隔離庫も履歴も実際より小さく見え続ける。
    private func healed(_ index: QuarantineIndex) -> QuarantineIndex {
        var healedIndex = index
        var changed = false
        for (runOffset, run) in index.runs.enumerated() {
            var entries = run.entries
            for (entryOffset, entry) in entries.enumerated() where entry.bytes == 0 {
                let path = root + "/" + run.runId + "/" + entry.quarantineRelativePath
                let measured = DirectoryMeter.measure(path: path).bytes
                guard measured > 0 else { continue }
                entries[entryOffset] = QuarantineEntry(
                    ruleId: entry.ruleId, originalPath: entry.originalPath,
                    quarantineRelativePath: entry.quarantineRelativePath, bytes: measured,
                    isDirectory: entry.isDirectory, movedAt: entry.movedAt)
                changed = true
            }
            if changed {
                healedIndex.runs[runOffset] = QuarantineRun(
                    runId: run.runId, createdAt: run.createdAt, expiresAt: run.expiresAt,
                    entries: entries)
            }
        }
        if changed { try? saveIndex(healedIndex) }
        return healedIndex
    }

    public func saveIndex(_ index: QuarantineIndex) throws {
        try JSONIO.writeAtomically(index, to: indexPath)
    }

    public func createRunDirectory(runId: String) throws -> String {
        let path = root + "/" + runId
        do {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw QuarantineError.cannotCreate(path)
        }
        return path
    }

    /// TTL を過ぎた run を実削除する。
    public func purgeExpired(now: Date = Date()) throws -> [PurgedRun] {
        var index = loadIndex()
        var purged: [PurgedRun] = []
        var remaining: [QuarantineRun] = []
        for run in index.runs {
            if run.expiresAt <= now {
                let path = root + "/" + run.runId
                try? FileManager.default.removeItem(atPath: path)
                purged.append(PurgedRun(runId: run.runId, bytes: run.totalBytes, itemCount: run.entries.count))
            } else {
                remaining.append(run)
            }
        }
        if !purged.isEmpty {
            index.runs = remaining
            try saveIndex(index)
        }
        return purged
    }

    /// 指定 run（または全 run）を即時削除する。
    public func purge(runId: String?, all: Bool, now: Date = Date()) throws -> [PurgedRun] {
        var index = loadIndex()
        var purged: [PurgedRun] = []
        var remaining: [QuarantineRun] = []
        for run in index.runs {
            let target = all || run.runId == runId
            if target {
                try? FileManager.default.removeItem(atPath: root + "/" + run.runId)
                purged.append(PurgedRun(runId: run.runId, bytes: run.totalBytes, itemCount: run.entries.count))
            } else {
                remaining.append(run)
            }
        }
        if let runId, !all, purged.isEmpty { throw QuarantineError.unknownRun(runId) }
        index.runs = remaining
        try saveIndex(index)
        return purged
    }

    /// 索引に無い run ディレクトリを検出する（削除はしない）。
    public func orphanDirectories() -> [String] {
        let known = Set(loadIndex().runs.map(\.runId))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return names.filter { name in
            name != "index.json" && !name.hasPrefix(".") && !known.contains(name)
        }.map { root + "/" + $0 }
    }
}

/// 実削除した run 1 件分の記録。
public struct PurgedRun: Sendable, Equatable {
    public let runId: String
    public let bytes: Int64
    public let itemCount: Int
}
