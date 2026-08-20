import Foundation

/// 外部コマンドの実行結果。
public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// `Process` の薄いラッパ。シェルを経由せず、実行ファイルと引数配列を直接渡す。
public enum CommandRunner {
    /// 出力の保存上限（監査ログには先頭 4KiB のみ残す）。
    public static let outputHeadLimit = 4096

    public static func run(_ spec: CommandSpec, timeoutSeconds: Int) -> CommandResult {
        guard let executable = resolveExecutable(spec.executable) else {
            return CommandResult(
                exitCode: 127, standardOutput: "", standardError: "executable not found", timedOut: false)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = spec.arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            // 起動と親側の書き込み端の close を不可分に行う。
            // 並行に spawn すると、別の子プロセスがこちらのパイプの書き込み端を継承してしまい、
            // 子が終了しても EOF が来ず read が永久に待つ（実測でデッドロックした）。
            spawnLock.lock()
            defer { spawnLock.unlock() }
            try process.run()
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
        } catch {
            return CommandResult(exitCode: 127, standardOutput: "", standardError: "\(error)", timedOut: false)
        }

        // パイプが詰まると子プロセスがブロックするため、読み出しは別スレッドで行う。
        let outBox = OutputBox()
        let errBox = OutputBox()
        let readGroup = DispatchGroup()
        for (pipe, box) in [(outPipe, outBox), (errPipe, errBox)] {
            readGroup.enter()
            let fd = pipe.fileHandleForReading.fileDescriptor
            DispatchQueue.global(qos: .utility).async {
                // FileHandle は閉じられた fd で例外を投げるため、read(2) を直接使う。
                var collected = Data()
                var buffer = [UInt8](repeating: 0, count: 16 * 1024)
                while true {
                    let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                    if count > 0 {
                        collected.append(contentsOf: buffer[0..<count])
                    } else if count == 0 || errno != EINTR {
                        break
                    }
                }
                box.set(String(bytes: collected, encoding: .utf8) ?? "")
                readGroup.leave()
            }
        }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                // TERM で終わらなければ 5 秒後に KILL する。
                let killDeadline = Date().addingTimeInterval(5)
                while process.isRunning && Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        // 読み出しにも上限を置く。ここで無限には待たない（出力は諦めても、実行結果は返す）。
        // 読み出しスレッドは EOF で自然に終わるため、こちらから fd を閉じて競合させない。
        _ = readGroup.wait(timeout: .now() + .seconds(timeoutSeconds + 5))

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: outBox.value,
            standardError: errBox.value,
            timedOut: timedOut
        )
    }

    /// 子プロセスの起動を直列化するためのロック（FD 継承の競合を避ける）。
    private static let spawnLock = NSLock()

    /// 絶対パスならそのまま、名前だけなら PATH から探す。
    public static func resolveExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":") {
            let candidate = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // Homebrew の既定 prefix は PATH に無いことがあるため明示的に見る。
        for candidate in ["/opt/homebrew/bin/" + name, "/usr/local/bin/" + name]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }
}

/// 読み出しスレッドと待ち合わせるための小さな箱。
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: String) {
        lock.lock()
        storage = newValue
        lock.unlock()
    }
}
