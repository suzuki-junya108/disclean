import ArgumentParser
import Foundation
import DiscleanKit

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan", abstract: "何がどれだけ空けられるかを読み取りだけで調べる（何も消しません）")

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "対象の Tier（A / B / C）。既定は A と B")
    var tier: String?

    @Option(name: .long, help: "特定のルールだけを対象にする（複数指定可）")
    var rule: [String] = []

    @Flag(name: .long, help: "スキャンキャッシュを使わない")
    var noCache = false

    func run() async throws {
        let context = Context(noUpdate: options.noUpdate)
        let tiers = try TierParser.parse(tier) ?? [.a, .b]
        let scanner = Scanner(env: context.env, config: context.config)
        let cancel = InterruptFlag.install()
        let result = await scanner.scan(
            catalog: context.catalog, tiers: tiers, ruleIds: Set(rule), useCache: !noCache,
            isCancelled: { cancel.isSet })

        if options.json {
            JSONOut.emit([
                "command": "scan",
                "items": result.items.map(JSONOut.item),
                "totals": ["bytes": result.totalBytes, "itemCount": result.readyItems.count],
                "capacity": JSONOut.capacity(result.capacity),
                "errors": result.errors.map { ["file": $0.file, "reason": $0.reason] },
            ])
        } else {
            ScanRenderer(out: context.out).render(result: result, context: context)
        }
        _ = await context.finishedUpdateOutcome()

        if result.interrupted { throw fail(.interrupted) }
        if !result.errors.isEmpty { throw fail(.invalidCatalog) }
        if result.readyItems.isEmpty && result.hasBlocked { throw fail(.permissionDenied) }
    }
}

enum TierParser {
    static func parse(_ raw: String?) throws -> Set<Tier>? {
        guard let raw else { return nil }
        var tiers: Set<Tier> = []
        for part in raw.split(separator: ",") {
            guard let tier = Tier(rawValue: part.trimmingCharacters(in: .whitespaces).uppercased()) else {
                throw ValidationError("unknown tier \"\(part)\" (expected A, B or C)")
            }
            tiers.insert(tier)
        }
        return tiers
    }
}

/// Ctrl-C を受けたら走査を止めて、そこまでの結果を出す。
final class InterruptFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()
    static let shared = InterruptFlag()

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    @discardableResult
    static func install() -> InterruptFlag {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler { InterruptFlag.shared.set() }
        source.resume()
        sources.append(source)
        return shared
    }

    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []
}
