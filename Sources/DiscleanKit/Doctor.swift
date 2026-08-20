import Foundation

/// 環境診断の結果。
public struct DoctorReport: Sendable {
    public struct Tool: Sendable {
        public let name: String
        public let found: Bool
        public let version: String?
    }

    public let fullDiskAccess: Bool
    public let tools: [Tool]
    public let configDir: String
    public let stateDir: String
    public let writable: Bool
    public let quarantineBytes: Int64
    public let runCount: Int
    public let orphanDirectories: [String]
    public let appliedCatalogVersion: Int
    public let lastCheckedAt: Date?
    public let autoUpdate: Bool
    public let osDrift: OSDriftReport
    public let warnings: [String]
}

/// FDA 判定・外部ツール検出・状態ディレクトリ・更新状態・OS 変化をまとめて調べる。
public struct Doctor: Sendable {
    private let env: DiscleanEnvironment
    private let config: Config

    /// `detect` を回す外部ツール（表示順）。
    static let probedTools: [(String, CommandSpec)] = [
        ("brew", CommandSpec(executable: "brew", arguments: ["--version"])),
        ("npm", CommandSpec(executable: "npm", arguments: ["--version"])),
        ("pnpm", CommandSpec(executable: "pnpm", arguments: ["--version"])),
        ("yarn", CommandSpec(executable: "yarn", arguments: ["--version"])),
        ("uv", CommandSpec(executable: "uv", arguments: ["--version"])),
        ("pip3", CommandSpec(executable: "pip3", arguments: ["--version"])),
        ("xcrun", CommandSpec(executable: "/usr/bin/xcrun", arguments: ["--version"])),
        ("docker", CommandSpec(executable: "docker", arguments: ["--version"])),
        ("tmutil", CommandSpec(executable: "/usr/bin/tmutil", arguments: ["version"])),
    ]

    public init(env: DiscleanEnvironment, config: Config) {
        self.env = env
        self.config = config
    }

    /// TCC.db を読み取り専用で開けるかどうかでフルディスクアクセスを判定する（内容は読まない）。
    public static func hasFullDiskAccess(home: String) -> Bool {
        let path = home + "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        return errno != EPERM && errno != EACCES ? false : false
    }

    public func run(catalog: RuleCatalog, updateState: UpdateState) -> DoctorReport {
        let fm = FileManager.default
        var warnings: [String] = []

        let tools = Doctor.probedTools.map { name, spec -> DoctorReport.Tool in
            let result = CommandRunner.run(spec, timeoutSeconds: 5)
            let version =
                result.succeeded
                ? result.standardOutput.split(separator: "\n").first.map(String.init)
                : nil
            return DoctorReport.Tool(name: name, found: result.succeeded, version: version)
        }

        let writable = fm.isWritableFile(atPath: env.stateDir) || !fm.fileExists(atPath: env.stateDir)
        if !writable { warnings.append("state directory is not writable: \(env.stateDir)") }

        let store = QuarantineStore(root: env.quarantineDir)
        let index = store.loadIndex()
        let orphans = store.orphanDirectories()
        if !orphans.isEmpty { warnings.append("orphan quarantine directories: \(orphans.count)") }

        for error in catalog.errors {
            warnings.append("rule error: \(error.file): \(error.reason)")
        }

        let drift = OSDrift(env: env).evaluate(catalog: catalog)
        if drift.changedSince != nil {
            warnings.append(
                "macOS build changed (\(drift.changedSince ?? "?") → \(env.osBuild)); scan cache was cleared")
        }
        if !drift.rulesMissingAfterOSChange.isEmpty {
            warnings.append("\(drift.rulesMissingAfterOSChange.count) rule path(s) disappeared after the OS change")
        }
        if updateState.lastCheckResult == .rejected, let reason = updateState.lastFailureReason {
            warnings.append("last update was rejected: \(reason)")
        }

        return DoctorReport(
            fullDiskAccess: Doctor.hasFullDiskAccess(home: env.home),
            tools: tools,
            configDir: env.configDir,
            stateDir: env.stateDir,
            writable: writable,
            quarantineBytes: index.runs.reduce(0) { $0 + $1.totalBytes },
            runCount: index.runs.count,
            orphanDirectories: orphans,
            appliedCatalogVersion: updateState.appliedCatalogVersion,
            lastCheckedAt: updateState.lastCheckedAt,
            autoUpdate: config.autoUpdate,
            osDrift: drift,
            warnings: warnings
        )
    }

    /// 状態ディレクトリを作る（冪等）。
    public func initializeDirectories() throws {
        let fm = FileManager.default
        for dir in [
            env.stateDir, env.quarantineDir, env.auditDir, env.cacheDir, env.updatesDir,
            env.configDir, env.rulesOverrideDir,
        ] {
            try fm.createDirectory(
                atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}
