import Foundation
import DiscleanKit

/// `disclean report --system`。システムデータの中身を、消さずに見せる。
extension ReportCommand {
    func runSystem(context: Context) async {
        let cancel = InterruptFlag.install()
        let progress = ProgressLine(out: context.out, home: context.env.home, quiet: options.json)
        let result = await SystemDataProbe(env: context.env)
            .scan(isCancelled: { cancel.isSet }, onProgress: progress.handler)
        progress.finish()

        if options.json {
            JSONOut.emit([
                "command": "report",
                "mode": "system",
                "items": result.items.map { item in
                    [
                        "id": item.kind.rawValue,
                        "title": item.text.title,
                        "bytes": jsonOrNull(item.bytes),
                        "state": item.state.rawValue,
                        "places": item.places,
                        "details": item.details,
                        "whatItIs": item.text.whatItIs,
                        "whyNotDeleted": item.text.whyNotDeleted,
                        "howToReduce": item.text.howToReduce,
                    ] as [String: Any]
                },
                "interrupted": result.interrupted,
                "blocked": result.blocked,
            ])
            return
        }
        SystemDataRenderer(out: context.out).render(result)
    }
}

struct SystemDataRenderer {
    let out: Output

    func render(_ result: SystemDataResult) {
        out.print(
            out.styled(
                out.japanese
                    ? "システムデータの中身です（ディスクリンはここを消しません）"
                    : "what is inside System Data (disclean never deletes these)",
                .bold))
        if result.interrupted {
            out.print(
                out.styled(
                    out.japanese ? "途中でやめました。測れたぶんだけを出しています。" : "stopped early; showing what was measured.",
                    .yellow))
        }
        for item in result.items {
            out.print()
            out.print("  \(pad(size(item), 10)) \(item.text.title)")
            out.print("    \(item.text.whatItIs)")
            for line in item.details {
                out.print(out.styled("    - \(line)", .dim))
            }
            // 「なぜ消さないか」は安全に関わるので、色で弱めない。
            out.print("    " + (out.japanese ? "消さない理由: " : "why not deleted: ") + item.text.whyNotDeleted)
            out.print(out.styled("    → \(item.text.howToReduce)", .cyan))
        }
        out.print()
        if result.blocked {
            out.print(
                out.styled(
                    out.japanese
                        ? "読めない場所がありました（フルディスクアクセスを付与すると測れます）"
                        : "some places could not be read (grant Full Disk Access to measure them)",
                    .yellow))
        }
        out.print(
            out.japanese
                ? "ディスクリンが片づけられるのは、このうちシミュレータ本体だけです（disclean scan に出ます）。"
                : "of these, disclean can clean only simulator runtimes (they appear in `disclean scan`).")
    }

    private func size(_ item: SystemDataItem) -> String {
        switch item.state {
        case .measured: Output.bytes(item.bytes ?? 0)
        case .absent: out.japanese ? "なし" : "none"
        case .blocked: out.japanese ? "読めません" : "unreadable"
        case .unknown: out.japanese ? "不明" : "unknown"
        }
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
