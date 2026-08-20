import Foundation
import DiscleanKit

/// S-02 環境診断。
struct DoctorRenderer {
    let out: Output

    func render(report: DoctorReport, context: Context) {
        renderPermissions(report)
        renderTools(report)
        renderDirectories(report)
        renderUpdates(report)
        renderOS(report)
        renderWarnings(report)
    }

    private func renderPermissions(_ report: DoctorReport) {
        out.print(out.styled(out.japanese ? "環境診断" : "environment", .bold))
        out.divider()
        let fda =
            report.fullDiskAccess
            ? out.styled(out.japanese ? "付与済み" : "granted", .green)
            : out.styled(out.japanese ? "未付与" : "not granted", .yellow)
        out.print((out.japanese ? "フルディスクアクセス: " : "Full Disk Access: ") + fda)
        if !report.fullDiskAccess {
            out.print(
                out.styled(
                    out.japanese
                        ? "  未付与のままでも Tier A の掃除は動きます。~/.Trash ~/Downloads ~/Documents ~/Desktop の"
                            + "大きさだけが測れません。"
                        : "  Tier A still works. Only the size of ~/.Trash ~/Downloads ~/Documents ~/Desktop is unmeasurable.",
                    .dim))
            out.print(
                out.styled(
                    out.japanese
                        ? "  付与するには: システム設定 → プライバシーとセキュリティ → フルディスクアクセス"
                        : "  Grant via: System Settings > Privacy & Security > Full Disk Access",
                    .dim))
        }

    }

    private func renderTools(_ report: DoctorReport) {
        out.print()
        out.print(out.japanese ? "外部ツール:" : "external tools:")
        for tool in report.tools {
            let mark = tool.found ? out.styled("✓", .green) : out.styled("-", .dim)
            out.print("  \(mark) \(pad(tool.name, 10)) \(tool.version ?? "")")
        }

    }

    private func renderDirectories(_ report: DoctorReport) {
        out.print()
        out.print(out.japanese ? "保存先:" : "directories:")
        out.print("  config  \(report.configDir)")
        out.print("  state   \(report.stateDir) " + (report.writable ? "" : out.styled("(書き込めません)", .red)))
        out.print(
            out.japanese
                ? "  隔離庫  \(Output.bytes(report.quarantineBytes)) / \(report.runCount) run"
                : "  quarantine \(Output.bytes(report.quarantineBytes)) / \(report.runCount) run(s)")

    }

    private func renderUpdates(_ report: DoctorReport) {
        out.print()
        out.print(out.japanese ? "更新:" : "updates:")
        out.print(
            out.japanese
                ? "  自動更新 \(report.autoUpdate ? "有効" : "無効") / 適用中カタログ \(report.appliedCatalogVersion)"
                : "  auto-update \(report.autoUpdate ? "on" : "off") / applied catalog \(report.appliedCatalogVersion)")
        if let checked = report.lastCheckedAt {
            out.print("  " + (out.japanese ? "最終確認 " : "last checked ") + Output.date(checked))
        } else {
            out.print("  " + (out.japanese ? "まだ確認していません" : "never checked"))
        }

    }

    private func renderOS(_ report: DoctorReport) {
        out.print()
        out.print(out.japanese ? "OS:" : "os:")
        out.print("  macOS \(report.osDrift.osVersion) (\(report.osDrift.osBuild))")
        if let changed = report.osDrift.changedSince {
            out.print(
                out.styled(
                    out.japanese
                        ? "  前回は \(changed) でした。掃除するパスが変わっている可能性があるため、キャッシュを捨てました。"
                        : "  changed from \(changed); scan cache cleared.",
                    .yellow))
        }
        if !report.osDrift.rulesMissingAfterOSChange.isEmpty {
            out.print(
                out.styled(
                    out.japanese
                        ? "  この OS で見つからなくなったルール: \(report.osDrift.rulesMissingAfterOSChange.count) 件"
                        : "  rules whose path disappeared: \(report.osDrift.rulesMissingAfterOSChange.count)",
                    .yellow))
            for missing in report.osDrift.rulesMissingAfterOSChange.prefix(10) {
                out.print(out.styled("    \(missing.ruleId): \(missing.path)", .dim))
            }
            out.print(
                out.styled(
                    out.japanese
                        ? "  disclean update で新しいルールを確認できます。" : "  run `disclean update` to check for new rules.",
                    .cyan))
        }
        if !report.osDrift.rulesDisabledByOS.isEmpty {
            out.print(
                out.styled(
                    out.japanese
                        ? "  この OS では無効なルール: \(report.osDrift.rulesDisabledByOS.count) 件"
                        : "  rules disabled on this OS: \(report.osDrift.rulesDisabledByOS.count)",
                    .dim))
        }

    }

    private func renderWarnings(_ report: DoctorReport) {
        if !report.warnings.isEmpty {
            out.print()
            for warning in report.warnings {
                out.print(out.styled("! " + warning, .yellow))
            }
        }
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
