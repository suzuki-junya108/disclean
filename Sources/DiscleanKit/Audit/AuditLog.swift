import Foundation

public enum AuditAction: String, Codable, Sendable {
    case apply
    case undo
    case purge
    case commandRun
    case catalogUpdate
    case appUpdate
}

public enum ResultKind: String, Codable, Sendable {
    case ok
    case skipped
    case failed
}

/// 監査ログ 1 行。追記専用。
public struct AuditRecord: Codable, Sendable {
    public let ts: Date
    public let action: AuditAction
    public let runId: String
    public let ruleId: String
    public let path: String?
    public let bytes: Int64
    public let result: ResultKind
    public let reason: String?
    public let toolExitCode: Int?
    public let toolOutputHead: String?
    public let osVersion: String
    public let osBuild: String
    public let catalogVersion: Int

    public init(
        ts: Date = Date(), action: AuditAction, runId: String, ruleId: String, path: String? = nil,
        bytes: Int64 = 0, result: ResultKind, reason: String? = nil, toolExitCode: Int? = nil,
        toolOutputHead: String? = nil, env: DiscleanEnvironment, catalogVersion: Int
    ) {
        self.ts = ts
        self.action = action
        self.runId = runId
        self.ruleId = ruleId
        self.path = path
        self.bytes = bytes
        self.result = result
        self.reason = reason
        self.toolExitCode = toolExitCode
        self.toolOutputHead = toolOutputHead
        self.osVersion = env.osVersion
        self.osBuild = env.osBuild
        self.catalogVersion = catalogVersion
    }
}

public enum AuditError: Error, Equatable {
    case cannotWrite(String)
}

/// JSONL 追記専用の監査ログ。書けない場合は破壊的操作を行わない。
public final class AuditLog: @unchecked Sendable {
    private let dir: String
    private let lock = NSLock()

    public init(dir: String) {
        self.dir = dir
    }

    private func currentFile(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone.current
        return dir + "/" + formatter.string(from: date) + ".jsonl"
    }

    /// 書き込み可能かを事前に確かめる（破壊的操作の前に必ず呼ぶ）。
    public func ensureWritable() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw AuditError.cannotWrite(dir)
        }
        guard fm.isWritableFile(atPath: dir) else { throw AuditError.cannotWrite(dir) }
    }

    public func append(_ record: AuditRecord) throws {
        try ensureWritable()
        let encoder = JSONIO.encoder(pretty: false)
        guard var data = try? encoder.encode(record) else { throw AuditError.cannotWrite(dir) }
        data.append(0x0A)
        let path = currentFile(record.ts)
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { throw AuditError.cannotWrite(path) }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            throw AuditError.cannotWrite(path)
        }
    }

    /// 期間を指定して読む。壊れた行は読み飛ばし、行番号を返す。
    public func read(since: Date?, until: Date?, action: AuditAction?) -> (records: [AuditRecord], corruptLines: [Int])
    {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return ([], []) }
        var records: [AuditRecord] = []
        var corrupt: [Int] = []
        var lineNumber = 0
        let decoder = JSONIO.decoder()
        for name in names.sorted() where name.hasSuffix(".jsonl") {
            guard let content = try? String(contentsOfFile: dir + "/" + name, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                lineNumber += 1
                guard let data = line.data(using: .utf8),
                    let record = try? decoder.decode(AuditRecord.self, from: data)
                else {
                    corrupt.append(lineNumber)
                    continue
                }
                if let since, record.ts < since { continue }
                if let until, record.ts > until { continue }
                if let action, record.action != action { continue }
                records.append(record)
            }
        }
        return (records.sorted { $0.ts > $1.ts }, corrupt)
    }
}
