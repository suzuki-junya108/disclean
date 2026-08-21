import ArgumentParser
import Foundation
import DiscleanKit

@main
struct Disclean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disclean",
        abstract: "macOS のディスクを、消す前に重さで見せて片づけます。",
        version: "disclean " + DiscleanVersion.current,
        subcommands: [
            ScanCommand.self, PlanCommand.self, ApplyCommand.self, UndoCommand.self,
            PurgeCommand.self, InspectCommand.self, HistoryCommand.self, ReportCommand.self, DoctorCommand.self,
            RulesCommand.self, UpdateCommand.self,
        ],
        defaultSubcommand: ScanCommand.self
    )
}

/// 全サブコマンド共通のオプション。
struct GlobalOptions: ParsableArguments {
    @Flag(name: .long, help: "機械可読な JSON を stdout に 1 オブジェクト出力する")
    var json = false

    @Flag(name: .long, help: "更新チェックを行わない（通信しない）")
    var noUpdate = false

    @Flag(name: .shortAndLong, help: "詳細な診断を stderr に出す")
    var verbose = false
}

/// 終了コードを持つ失敗。メッセージは stderr に出し、ArgumentParser の終了コードへ変換する。
func fail(_ code: DiscleanExitCode, _ message: String? = nil) -> Error {
    if let message, !message.isEmpty {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
    return ArgumentParser.ExitCode(code.rawValue)
}
