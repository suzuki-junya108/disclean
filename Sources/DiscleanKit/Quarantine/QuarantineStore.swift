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
    ///
    /// 消すのは 1 ファイルずつ。まとめて消すより少しだけ遅いが、
    /// 「いまどれを消しているか」「あと何件か」を出せる（`onProgress`）。
    public func purge(
        runId: String?, all: Bool, now: Date = Date(),
        onProgress: WorkProgressHandler = ignoreProgress
    ) throws -> [PurgedRun] {
        var index = loadIndex()
        var purged: [PurgedRun] = []
        var remaining: [QuarantineRun] = []

        // 先に数える。数えるのは一覧を取るだけで、中身は読まない。
        onProgress(WorkProgress(step: .counting))
        var plans: [String: PurgePlan] = [:]
        var total = 0
        for run in index.runs where all || run.runId == runId {
            let plan = PurgePlan(root: root, run: run)
            plans[run.runId] = plan
            total += plan.files.count
        }

        var completed = 0
        for run in index.runs {
            guard all || run.runId == runId else {
                remaining.append(run)
                continue
            }
            if let plan = plans[run.runId] {
                for file in plan.files {
                    // 見せるのは隔離庫の中の置き場所ではなく、元あった場所。
                    onProgress(
                        WorkProgress(
                            step: .deleting, ruleId: file.ruleId, path: file.origin,
                            completed: completed, total: total))
                    unlink(file.path)
                    completed += 1
                }
                // 中身を消してから、入れ物を深い順にたたむ。
                for directory in plan.directories.reversed() { rmdir(directory) }
            }
            try? FileManager.default.removeItem(atPath: root + "/" + run.runId)
            purged.append(PurgedRun(runId: run.runId, bytes: run.totalBytes, itemCount: run.entries.count))
        }
        if let runId, !all, purged.isEmpty { throw QuarantineError.unknownRun(runId) }
        index.runs = remaining
        try saveIndex(index)
        onProgress(
            WorkProgress(step: .deleting, path: "", completed: completed, total: max(total, completed)))
        return purged
    }

    /// 1 つの run について「何を消すか」を先に並べたもの。
    /// 進捗を出すには消す前に総数が要る。隔離した項目ごとに辿るので、
    /// ファイル 1 つずつに「元はどこにあったか」を付けられる。
    private struct PurgePlan {
        var files: [PurgeTarget] = []
        var directories: [String] = []

        init(root: String, run: QuarantineRun) {
            let runRoot = root + "/" + run.runId
            for entry in run.entries {
                let base = runRoot + "/" + entry.quarantineRelativePath
                add(base: base, origin: entry.originalPath, ruleId: entry.ruleId)
            }
        }

        private mutating func add(base: String, origin: String, ruleId: String) {
            var st = stat()
            guard lstat(base, &st) == 0 else { return }
            guard (st.st_mode & S_IFMT) == S_IFDIR else {
                files.append(PurgeTarget(path: base, origin: origin, ruleId: ruleId))
                return
            }
            directories.append(base)
            guard let walker = FileManager.default.enumerator(atPath: base) else { return }
            for case let relative as String in walker {
                let full = base + "/" + relative
                var child = stat()
                guard lstat(full, &child) == 0 else { continue }
                if (child.st_mode & S_IFMT) == S_IFDIR {
                    directories.append(full)
                } else {
                    files.append(
                        PurgeTarget(path: full, origin: origin + "/" + relative, ruleId: ruleId))
                }
            }
        }
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

/// 消す対象 1 件。進捗には隔離庫の中の置き場所ではなく、元あった場所を見せる。
private struct PurgeTarget {
    let path: String
    let origin: String
    let ruleId: String
}
