import Foundation

/// 大きいもの 1 件の「まとめかた」。
///
/// 実測すると、ホームの中で大きいファイルをそのまま並べた一覧は、ほとんどが
/// `node_modules` や `.app` の**中の部品**で埋まる（1.1M 件のうち 200MB 超は 5 件、
/// 5 件とも部品置き場の中だった）。部品を 1 個ずつ見せても判断できないし、
/// 1 個だけ消せば壊れる。だから「持ち主」でまとめてから見せる。
public enum BigItemGroup: String, Codable, Sendable, CaseIterable {
    /// ひとかたまりで扱う入れ物（アプリ・写真ライブラリ・書き出しの束）。中はばらさない。
    case bundle
    /// 部品やビルドの出力が入る場所。まとめて 1 件として扱う。
    case parts
    /// 単体のファイル。持ち主のいない、それ自体が中身のもの。
    case file

    public var labelJa: String {
        switch self {
        case .bundle: "ひとかたまり"
        case .parts: "部品・ビルドの置き場"
        case .file: "ファイル"
        }
    }

    public var label: String {
        switch self {
        case .bundle: "Bundle"
        case .parts: "Build / dependency store"
        case .file: "File"
        }
    }
}

/// 見つけた大きいもの 1 件。
public struct BigItem: Codable, Sendable, Equatable, Identifiable {
    public let path: String
    public let name: String
    public let bytes: Int64
    /// 入れ物なら中のファイル数。単体ファイルなら 1。
    public let fileCount: Int
    public let isDirectory: Bool
    /// 中で最後に更新された時刻。「もう何年も触っていない」を言うために使う。
    public let modified: Date?
    public let kind: FileKind
    public let group: BigItemGroup
    /// 何を目印にまとめたか（`node_modules` / `.app` など）。単体ファイルは nil。
    public let marker: String?
    /// 消すとどうなるか。押す前に読める 1 文。
    public let adviceJa: String
    public let advice: String

    public var id: String { path }

    public init(
        path: String, name: String, bytes: Int64, fileCount: Int, isDirectory: Bool,
        modified: Date?, kind: FileKind, group: BigItemGroup, marker: String?,
        adviceJa: String, advice: String
    ) {
        self.path = path
        self.name = name
        self.bytes = bytes
        self.fileCount = fileCount
        self.isDirectory = isDirectory
        self.modified = modified
        self.kind = kind
        self.group = group
        self.marker = marker
        self.adviceJa = adviceJa
        self.advice = advice
    }

    public func displayAdvice(japanese: Bool) -> String { japanese ? adviceJa : advice }

    /// 最後にさわってからの日数。分からなければ nil。
    public func ageDays(now: Date = Date()) -> Int? {
        guard let modified else { return nil }
        return max(0, Int(now.timeIntervalSince(modified) / 86_400))
    }
}

/// 目印の表と、そこから引く「消すとどうなるか」。
///
/// 判定はディレクトリ名だけで行う（中身は開かない）。当たらなかったものは
/// ふつうのフォルダとして 1 段下りるので、外れても取りこぼしにはならない。
public enum BigItemMarkers {
    /// 中をばらさずに 1 件として扱う入れ物。拡張子で判定する。
    static let bundleSuffixes = [
        ".app", ".framework", ".xcarchive", ".xcresult", ".dSYM", ".bundle", ".playground",
        ".xcodeproj", ".xcworkspace", ".photoslibrary", ".sparsebundle", ".fcpbundle",
        ".imovielibrary", ".theater", ".logicx", ".band", ".aplibrary", ".musiclibrary",
        ".tvlibrary", ".rtfd", ".key", ".numbers", ".pages", ".pkg", ".mpkg",
    ]

    /// 部品・ビルドの出力が入るフォルダ。名前がそのまま一致したときだけ当てる。
    static let partsNames: Set<String> = [
        "node_modules", ".pnpm-store", ".yarn", ".npm", ".venv", "venv", ".git", ".build",
        "build", "dist", "out", "target", "vendor", "coverage", "DerivedData", "Pods",
        "Carthage", ".gradle", ".tox", "__pycache__", ".next", ".nuxt", ".turbo",
        ".parcel-cache", ".angular", ".svelte-kit", ".astro", ".vite", ".swiftpm",
        ".mypy_cache", ".pytest_cache", ".ruff_cache", ".terraform", ".stack-work",
        ".expo", ".cargo", ".rustup", ".m2", ".ivy2", ".cache",
    ]

    /// 入れ物の目印。当たらなければ nil（ふつうのフォルダとして下りる）。
    public static func bundle(for name: String) -> String? {
        let lower = name.lowercased()
        return bundleSuffixes.first { lower.hasSuffix($0.lowercased()) }
    }

    /// 部品置き場の目印。当たらなければ nil。
    public static func parts(for name: String) -> String? {
        partsNames.contains(name) ? name : nil
    }

    /// 「消すとどうなるか」。安全に関わる情報なので、飾らずに平文で書く。
    public static func advice(group: BigItemGroup, marker: String?, kind: FileKind) -> (ja: String, en: String) {
        if let marker, let special = special[marker.lowercased()] { return special }
        switch group {
        case .bundle:
            return (
                "中身がひとまとまりの入れ物です。ばらさずに、まるごと扱ってください。",
                "A bundle. Treat it as one unit rather than opening it up."
            )
        case .parts:
            return (
                "ソフトウェアの部品やビルドの出力が入る場所です。多くは作り直せますが、消す前に中身を確かめてください。",
                "Holds dependencies or build output. Usually reproducible, but check before removing."
            )
        case .file:
            return (kind.explanationJa, kind.explanation)
        }
    }

    /// 目印ごとの言い方。ふつうの言葉が足りない場所だけ、個別に書く。
    private static let special: [String: (ja: String, en: String)] = [
        ".git": (
            "変更の履歴です。消すと、この場所では過去に戻れなくなります（GitHub などに上げてあれば取り直せます）。",
            "The change history. Removing it loses the past here (recoverable if pushed to a remote)."
        ),
        "node_modules": (
            "取り寄せた部品です。`npm install` などで入れ直せます。",
            "Fetched dependencies. `npm install` (or similar) puts them back."
        ),
        ".venv": (
            "Python の作業用の環境です。作り直せます。",
            "A Python virtual environment. It can be recreated."
        ),
        "venv": (
            "Python の作業用の環境です。作り直せます。",
            "A Python virtual environment. It can be recreated."
        ),
        "deriveddata": (
            "Xcode がビルドで作ったものです。次のビルドで作り直されます。",
            "Xcode build output. The next build recreates it."
        ),
        ".app": (
            "アプリ本体です。消すとそのアプリは使えなくなります（入れ直せます）。",
            "An application. Removing it uninstalls the app (it can be installed again)."
        ),
        ".photoslibrary": (
            "写真がまるごと入っています。ほかに控えがあるか、必ず確かめてください。",
            "Your entire photo library. Make sure a copy exists elsewhere before touching it."
        ),
        ".fcpbundle": (
            "Final Cut の作業ファイルがまるごと入っています。ほかに控えがあるか確かめてください。",
            "A Final Cut library. Make sure a copy exists elsewhere."
        ),
        ".imovielibrary": (
            "iMovie の作業ファイルがまるごと入っています。ほかに控えがあるか確かめてください。",
            "An iMovie library. Make sure a copy exists elsewhere."
        ),
        ".logicx": (
            "Logic の曲データです。ほかに控えがあるか確かめてください。",
            "A Logic project. Make sure a copy exists elsewhere."
        ),
        ".xcarchive": (
            "配布したときのビルドの控えです。過去の版を調べるときだけ使います。",
            "An archived build. Only needed when investigating a shipped version."
        ),
        ".dsym": (
            "クラッシュを読み解くための記号表です。過去の版を調べるときだけ使います。",
            "Debug symbols. Only needed when investigating a shipped version."
        ),
        ".xcresult": (
            "テストを走らせたときの記録です。走らせ直せば、また作られます。",
            "A test run result. Running the tests again recreates it."
        ),
    ]
}
