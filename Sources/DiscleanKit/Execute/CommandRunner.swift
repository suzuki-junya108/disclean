import Foundation

/// 外部コマンドの実行結果。
public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// 外部コマンドの実行。`posix_spawn` と `poll` で自前に行う。
///
/// Foundation の `Process` を使わないのは、並列に多数のコマンドを走らせたときに
/// 出力の取りこぼしと終了通知の遅延が実測で起きたため。ここでは
/// - 子プロセスに渡す fd を明示し、`POSIX_SPAWN_CLOEXEC_DEFAULT` で他の fd を継承させない
/// - 親側の書き込み端を必ず閉じ、EOF を保証する
/// - 読み出しと終了待ちを 1 スレッドで行う（スレッドプールを枯渇させない）
/// の 3 点を守る。
public enum CommandRunner {
    /// 出力の保存上限（監査ログには先頭 4KiB のみ残す）。
    public static let outputHeadLimit = 4096

    public static func run(_ spec: CommandSpec, timeoutSeconds: Int) -> CommandResult {
        guard let executable = resolveExecutable(spec.executable) else {
            return CommandResult(
                exitCode: 127, standardOutput: "", standardError: "executable not found", timedOut: false)
        }

        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else {
            return CommandResult(exitCode: 126, standardOutput: "", standardError: "pipe failed", timedOut: false)
        }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0])
            close(outPipe[1])
            return CommandResult(exitCode: 126, standardOutput: "", standardError: "pipe failed", timedOut: false)
        }

        let spawn = spawnChild(
            executable: executable, arguments: spec.arguments,
            stdoutWrite: outPipe[1], stderrWrite: errPipe[1])

        // 親は書き込み端を必ず閉じる。閉じないと子が終了しても EOF が来ない。
        close(outPipe[1])
        close(errPipe[1])

        guard case .success(let pid) = spawn else {
            close(outPipe[0])
            close(errPipe[0])
            if case .failure(let code) = spawn {
                return CommandResult(
                    exitCode: 126, standardOutput: "",
                    standardError: "spawn failed: \(String(cString: strerror(code)))", timedOut: false)
            }
            return CommandResult(exitCode: 126, standardOutput: "", standardError: "spawn failed", timedOut: false)
        }

        return collect(
            pid: pid, stdoutRead: outPipe[0], stderrRead: errPipe[0], timeoutSeconds: timeoutSeconds)
    }

    private enum SpawnOutcome {
        case success(pid_t)
        case failure(Int32)
    }

    private static func spawnChild(
        executable: String, arguments: [String], stdoutWrite: Int32, stderrWrite: Int32
    ) -> SpawnOutcome {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdoutWrite, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrWrite, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // 明示した fd 以外は子に渡さない。他のコマンドのパイプを握られると EOF が来なくなる。
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv: [String] = [executable] + arguments
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        defer { for pointer in cArgs where pointer != nil { free(pointer) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, &cArgs, environ)
        return status == 0 ? .success(pid) : .failure(status)
    }

    /// 出力の読み出しと終了待ちを 1 スレッドで行う。
    private static func collect(
        pid: pid_t, stdoutRead: Int32, stderrRead: Int32, timeoutSeconds: Int
    ) -> CommandResult {
        var out = Data()
        var err = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let fds = [
            pollfd(fd: stdoutRead, events: Int16(POLLIN), revents: 0),
            pollfd(fd: stderrRead, events: Int16(POLLIN), revents: 0),
        ]
        var open = [true, true]
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var timedOut = false
        var killed = false

        while open[0] || open[1] {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 && !timedOut {
                timedOut = true
                kill(pid, SIGTERM)
            }
            if timedOut && !killed && remaining <= -5 {
                killed = true
                kill(pid, SIGKILL)
            }
            // タイムアウト後も、子が終わるまでは短い間隔で待ち続ける（取りこぼしを避ける）。
            let waitMs: Int32 = timedOut ? 200 : Int32(max(50, min(1000, remaining * 1000)))

            var active = fds.enumerated().filter { open[$0.offset] }.map(\.element)
            let ready = poll(&active, nfds_t(active.count), waitMs)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }

            for polled in active {
                guard polled.revents != 0 else { continue }
                let index = polled.fd == stdoutRead ? 0 : 1
                let count = buffer.withUnsafeMutableBytes { read(polled.fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    if index == 0 {
                        out.append(contentsOf: buffer[0..<count])
                    } else {
                        err.append(contentsOf: buffer[0..<count])
                    }
                } else if count == 0 || errno != EINTR {
                    open[index] = false
                }
            }
        }

        close(stdoutRead)
        close(stderrRead)

        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        let exitCode: Int32
        if status & 0x7F == 0 {
            exitCode = (status >> 8) & 0xFF
        } else {
            exitCode = 128 + (status & 0x7F)  // シグナルで終了した場合
        }

        return CommandResult(
            exitCode: exitCode,
            standardOutput: String(bytes: out, encoding: .utf8) ?? "",
            standardError: String(bytes: err, encoding: .utf8) ?? "",
            timedOut: timedOut
        )
    }

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
