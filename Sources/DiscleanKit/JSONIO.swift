import Foundation

/// JSON の読み書き。出力は常にキー順ソート + ISO8601（ミリ秒・オフセット付き）。
public enum JSONIO {
    public static func encoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting =
            pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = JSONIO.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date: \(text)")
        }
        return decoder
    }

    /// ISO8601（ミリ秒・タイムゾーンオフセット付き）の相互変換。
    /// `ISO8601DateFormatter` は Sendable ではないため、ロックで保護した 1 個を共有する。
    public static func string(from date: Date) -> String { formatters.string(from: date) }

    public static func date(from text: String) -> Date? { formatters.date(from: text) }

    private static let formatters = ISO8601Box()

    public static func read<T: Decodable>(_ type: T.Type, at path: String) throws -> T {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder().decode(type, from: data)
    }

    /// 一時ファイルへ書き、fsync してから rename で置換する（途中終了しても旧版が残る）。
    public static func writeAtomically<T: Encodable>(_ value: T, to path: String, permissions: Int16 = 0o600) throws {
        let data = try encoder().encode(value)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir + "/.tmp-" + UUID().uuidString
        FileManager.default.createFile(
            atPath: tmp, contents: nil, attributes: [.posixPermissions: NSNumber(value: permissions)])
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tmp))
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        _ = try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.moveItem(atPath: tmp, toPath: path)
    }
}

/// `ISO8601DateFormatter` をロックで包み、プロセス全体で 1 個だけ使う。
private final class ISO8601Box: @unchecked Sendable {
    private let lock = NSLock()
    private let withFraction: ISO8601DateFormatter
    private let withoutFraction: ISO8601DateFormatter

    init() {
        withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return withFraction.string(from: date)
    }

    func date(from text: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }
}
