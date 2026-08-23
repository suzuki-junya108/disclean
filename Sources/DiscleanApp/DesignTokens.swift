import SwiftUI

/// HEAVY CANDY のトークン（`docs/design-system.md` が唯一の出典）。
/// View に色・寸法のリテラルを直接書かない。
enum Tokens {
    // MARK: - 色（§2.1）

    static let ink = Color(hex: 0x16_12_1F)
    static let paper = Color(hex: 0xFF_F2_DC)
    static let void = Color(hex: 0x10_0D_18)
    static let cardDark = Color(hex: 0x1C_17_26)
    static let lime = Color(hex: 0xC6_F8_33)
    static let sunbeam = Color(hex: 0xFF_D2_3F)
    static let sky = Color(hex: 0x4C_D8_FF)
    static let grape = Color(hex: 0x6C_2B_EA)
    static let tomato = Color(hex: 0xFF_4A_32)
    static let bubblegum = Color(hex: 0xFF_6F_B5)

    // MARK: - 形（§4）

    static let cardRadius: CGFloat = 22
    static let pillRadius: CGFloat = 999
    static let chunkRadius: CGFloat = 14
    static let keylineWidth: CGFloat = 3
    static let cardShadowOffset: CGFloat = 6
    static let chipShadowOffset: CGFloat = 4

    /// チャンクの高さは容量に比例する（§5.1）。
    static func chunkHeight(bytes: Int64) -> CGFloat {
        let gigabytes = Double(bytes) / 1_000_000_000
        return min(320, max(48, 48 + gigabytes * 3.2))
    }

    /// レバーを発火させるドラッグ量（§5.2）。
    static let leverThrow: CGFloat = 120

    // MARK: - 書体（§3）

    static func display(_ size: CGFloat) -> Font {
        custom(
            Names.display, size: size,
            fallback: .system(size: size, weight: .heavy, design: .rounded))
    }

    static func body(_ size: CGFloat = 15) -> Font {
        custom(Names.body, size: size, fallback: .system(size: size, weight: .regular, design: .rounded))
    }

    static func bodyBold(_ size: CGFloat = 15) -> Font {
        custom(Names.bodyBold, size: size, fallback: .system(size: size, weight: .bold, design: .rounded))
    }

    static func data(_ size: CGFloat = 12) -> Font {
        custom(
            Names.data, size: size, fallback: .system(size: size, weight: .semibold, design: .monospaced))
    }

    /// 容量の数字は、量が増えるほど字面を重くする（LP と同じ考え方）。
    /// 同梱フォントが無い環境ではウェイトで代替し、意味だけを残す。
    static func weightedData(_ size: CGFloat, bytes: Int64) -> Font {
        let gigabytes = Double(bytes) / 1_000_000_000
        let heaviness = min(1, gigabytes / 100)
        if let resolved = Names.resolve(Names.data, size: size) {
            return Font.custom(resolved, size: size)
                .width(.init((82 + heaviness * 30) / 100))
        }
        return .system(size: size, weight: heaviness > 0.35 ? .black : .semibold, design: .monospaced)
    }

    /// 同梱フォントがあれば使い、無ければシステムのフォールバックで描く（機能は損なわない）。
    private static func custom(_ candidates: [String], size: CGFloat, fallback: Font) -> Font {
        guard let name = Names.resolve(candidates, size: size) else { return fallback }
        return Font.custom(name, size: size)
    }

    /// 書体の名前。可変フォントは名前付きインスタンスごとに PostScript 名が変わるため、
    /// 候補を順に試す。同梱・システム導入・どちらでも同じ見た目になるようにする。
    enum Names {
        static let display = [
            "BricolageGrotesque-96ptExtraBold_ExtraBold",   // 同梱の可変フォント
            "BricolageGrotesque-ExtraBold",                 // 利用者が別途入れている場合
            "BricolageGrotesque-Regular",
        ]
        static let body = ["ZenMaruGothic-Regular"]
        static let bodyBold = ["ZenMaruGothic-Bold"]
        static let data = [
            "MartianMono-SemiExpandedRegular_SemiBold",
            "MartianMono-SemiBold",
            "MartianMono-SemiExpandedRegular",
        ]

        /// 実際に使える最初の名前を返す。1 つも無ければ nil（＝システム書体で描く）。
        static func resolve(_ candidates: [String], size: CGFloat) -> String? {
            candidates.first { NSFont(name: $0, size: size) != nil }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

/// 明暗で入れ替わる地とキーライン。キャンディ 6 色は値を変えない（§2.3）。
struct Surface {
    let scheme: ColorScheme

    var background: Color { scheme == .dark ? Tokens.void : Tokens.paper }
    var card: Color { scheme == .dark ? Tokens.cardDark : Tokens.paper }
    var keyline: Color { scheme == .dark ? Tokens.paper : Tokens.ink }
    var text: Color { scheme == .dark ? Tokens.paper : Tokens.ink }
    /// 明色チップの上の文字は常に ink（§2.2 の 8 通りのみ）。
    var onCandy: Color { Tokens.ink }
    var focus: Color { scheme == .dark ? Tokens.sky : Tokens.grape }
}
