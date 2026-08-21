import Foundation
import Testing

@testable import DiscleanKit

@Suite("CommandRunner: 並列でも出力と終了コードを落とさない")
struct CommandRunnerSmokeTests {
    @Test("標準出力を取り、終了コード 0 を返す")
    func echo() {
        let result = CommandRunner.run(
            CommandSpec(executable: "/bin/echo", arguments: ["hello"]), timeoutSeconds: 5)
        let detail = "exit=\(result.exitCode) timedOut=\(result.timedOut)"
        #expect(result.exitCode == 0, Comment(rawValue: detail))
        #expect(!result.timedOut, Comment(rawValue: detail))
        #expect(
            result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "hello",
            Comment(rawValue: result.standardOutput.debugDescription))
        #expect(result.succeeded)
    }

    @Test("タイムアウトすると打ち切る")
    func timeout() {
        let started = Date()
        let result = CommandRunner.run(
            CommandSpec(executable: "/bin/sleep", arguments: ["10"]), timeoutSeconds: 1)
        #expect(result.timedOut)
        #expect(Date().timeIntervalSince(started) < 8)
    }

    @Test("並列に走らせても、それぞれの出力が混ざらず取りこぼされない")
    func parallelOutputs() async {
        let results = await withTaskGroup(of: (Int, CommandResult).self) { group in
            for index in 0..<24 {
                group.addTask {
                    (
                        index,
                        CommandRunner.run(
                            CommandSpec(executable: "/bin/echo", arguments: ["out-\(index)"]),
                            timeoutSeconds: 10)
                    )
                }
            }
            var collected: [(Int, CommandResult)] = []
            for await value in group { collected.append(value) }
            return collected
        }
        #expect(results.count == 24)
        for (index, result) in results {
            #expect(result.exitCode == 0)
            #expect(!result.timedOut)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "out-\(index)")
        }
    }
}
