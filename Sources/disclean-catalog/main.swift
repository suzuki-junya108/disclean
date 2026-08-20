import CryptoKit
import Foundation
import DiscleanKit

// 配信用カタログの作成と署名を行う開発者向けツール。
// 製品には含めない（Package.swift の products に載せていない）。
//
//   disclean-catalog keygen --out keys/           鍵ペアを作る（秘密鍵は絶対にコミットしない）
//   disclean-catalog build --rules-dir ... --out-dir ... --catalog-version N --key-file ...

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: "--" + name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func options(_ name: String, in args: [String]) -> [String] {
    var values: [String] = []
    for (index, value) in args.enumerated() where value == "--" + name && index + 1 < args.count {
        values.append(args[index + 1])
    }
    return values
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    die("usage: disclean-catalog <keygen|build|verify> [options]")
}

switch command {
case "keygen":
    let outDir = option("out", in: arguments) ?? "."
    let keyId = option("key-id", in: arguments) ?? "key-\(Int(Date().timeIntervalSince1970))"
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(
        atPath: outDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let privatePath = outDir + "/\(keyId).private.key"
    FileManager.default.createFile(
        atPath: privatePath,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600])
    let publicEntry: [[String: Any]] = [
        [
            "keyId": keyId,
            "publicKey": key.publicKey.rawRepresentation.base64EncodedString(),
        ]
    ]
    let publicData = try JSONSerialization.data(
        withJSONObject: publicEntry, options: [.prettyPrinted, .sortedKeys])
    try publicData.write(to: URL(fileURLWithPath: outDir + "/\(keyId).release-keys.json"))
    print("keyId: \(keyId)")
    print("private: \(privatePath)  (never commit this file)")
    print("public:  \(outDir)/\(keyId).release-keys.json")

case "build":
    guard let rulesDir = option("rules-dir", in: arguments),
        let outDir = option("out-dir", in: arguments),
        let versionText = option("catalog-version", in: arguments),
        let catalogVersion = Int(versionText),
        let keyFile = option("key-file", in: arguments),
        let keyId = option("key-id", in: arguments)
    else {
        die(
            "usage: disclean-catalog build --rules-dir <dir> --out-dir <dir> --catalog-version <n> "
                + "--key-file <path> --key-id <id> [--min-disclean-version x.y.z] [--app-version x.y.z] "
                + "[--app-asset name=url=sha256=bytes] [--revoke ruleId] [--valid-days 90]")
    }
    let fm = FileManager.default
    try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    // 1) ルール JSON をアーカイブにまとめる（rules/ 配下に置く）。
    let archiveName = "catalog-\(catalogVersion).tar.gz"
    let archivePath = outDir + "/" + archiveName
    let staging = NSTemporaryDirectory() + "disclean-catalog-" + UUID().uuidString
    try fm.createDirectory(atPath: staging + "/rules", withIntermediateDirectories: true)
    var files: [[String: Any]] = []
    for name in try fm.contentsOfDirectory(atPath: rulesDir).sorted() where name.hasSuffix(".json") {
        let data = try Data(contentsOf: URL(fileURLWithPath: rulesDir + "/" + name))
        try data.write(to: URL(fileURLWithPath: staging + "/rules/" + name))
        files.append(["name": name, "sha256": sha256Hex(data), "bytes": data.count])
    }
    let tar = Process()
    tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    tar.arguments = ["-czf", archivePath, "-C", staging, "rules"]
    try tar.run()
    tar.waitUntilExit()
    guard tar.terminationStatus == 0 else { die("tar failed") }
    try? fm.removeItem(atPath: staging)

    let archiveData = try Data(contentsOf: URL(fileURLWithPath: archivePath))
    let now = Date()
    let validDays = Int(option("valid-days", in: arguments) ?? "90") ?? 90

    var manifest: [String: Any] = [
        "schemaVersion": 1,
        "catalogVersion": catalogVersion,
        "publishedAt": JSONIO.string(from: now),
        "expiresAt": JSONIO.string(from: now.addingTimeInterval(TimeInterval(validDays) * 86_400)),
        "minDiscleanVersion": option("min-disclean-version", in: arguments) ?? "0.1.0",
        "keyId": keyId,
        "archive": ["name": archiveName, "sha256": sha256Hex(archiveData), "bytes": archiveData.count],
        "files": files,
        "revocations": options("revoke", in: arguments),
    ]
    if let appVersion = option("app-version", in: arguments) {
        var assets: [[String: Any]] = []
        for spec in options("app-asset", in: arguments) {
            let parts = spec.split(separator: "=", maxSplits: 3).map(String.init)
            guard parts.count == 4, let bytes = Int(parts[3]) else { die("bad --app-asset: \(spec)") }
            assets.append(["name": parts[0], "url": parts[1], "sha256": parts[2], "bytes": bytes])
        }
        manifest["latestApp"] = [
            "version": appVersion,
            "minMacOS": option("app-min-macos", in: arguments) ?? "14.0",
            "assets": assets,
        ]
    }

    // 2) 署名対象のバイト列を確定させる（受信側はこのバイト列をそのまま検証する）。
    let body = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    let manifestPath = outDir + "/catalog-manifest.json"
    try body.write(to: URL(fileURLWithPath: manifestPath))

    let keyText = try String(contentsOfFile: keyFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyData = Data(base64Encoded: keyText),
        let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    else {
        die("cannot read private key: \(keyFile)")
    }
    let signature = try privateKey.signature(for: body)
    try Data(signature.base64EncodedString().utf8)
        .write(to: URL(fileURLWithPath: manifestPath + ".sig"))

    print("catalogVersion: \(catalogVersion)")
    print("manifest: \(manifestPath)")
    print("archive:  \(archivePath)")
    print("publicKey: \(privateKey.publicKey.rawRepresentation.base64EncodedString())")

case "verify":
    guard let manifestPath = option("manifest", in: arguments),
        let keysPath = option("keys", in: arguments)
    else {
        die("usage: disclean-catalog verify --manifest <path> --keys <release-keys.json>")
    }
    let body = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let signature = try String(contentsOfFile: manifestPath + ".sig", encoding: .utf8)
    let keys = try JSONIO.decoder().decode(
        [ReleaseKey].self, from: try Data(contentsOf: URL(fileURLWithPath: keysPath)))
    switch ManifestVerifier(trustedKeys: keys).verifyManifest(data: body, signatureBase64: signature) {
    case .success(let manifest):
        print("ok: catalog \(manifest.catalogVersion), expires \(JSONIO.string(from: manifest.expiresAt))")
    case .failure(let failure):
        die("verification failed: \(failure.rawValue)")
    }

default:
    die("unknown command: \(command)")
}
