// LP の OG 画像（1200x630）を描く。HEAVY CANDY の地・キーライン・塊で構成する。
// 使い方: swift tools/icon/render-og.swift <出力先パス>
import AppKit
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "site/og.png"

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1)
}

let ink = color(0x16121F)
let paper = color(0xFFF2DC)
let lime = color(0xC6F833)
let sunbeam = color(0xFFD23F)
let sky = color(0x4CD8FF)
let grape = color(0x6C2BEA)

let width = 1200, height = 630
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func chunk(_ rect: NSRect, fill: NSColor) {
    ink.setFill()
    rounded(rect.offsetBy(dx: 8, dy: -8), 14).fill()
    fill.setFill()
    rounded(rect, 14).fill()
    ink.setStroke()
    let stroke = rounded(rect, 14)
    stroke.lineWidth = 5
    stroke.stroke()
}

// 地 + 網点
lime.setFill()
NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
ink.withAlphaComponent(0.09).setFill()
var y: CGFloat = 8
while y < CGFloat(height) {
    var x: CGFloat = 8
    while x < CGFloat(width) {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 3, height: 3)).fill()
        x += 18
    }
    y += 18
}

// 文字
func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          mono: Bool = false, tracking: CGFloat = 0) {
    let font: NSFont = mono
        ? (NSFont.monospacedSystemFont(ofSize: size, weight: weight))
        : (NSFont(name: "HiraMaruProN-W6", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight))
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .kern: tracking,
    ]
    NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: x, y: y))
}

draw("MACOS 14+ / APPLE SILICON · INTEL", x: 72, y: 508, size: 20, weight: .semibold, color: ink,
     mono: true, tracking: 2)
draw("そのギガバイト、", x: 68, y: 396, size: 78, weight: .black, color: ink, tracking: -3)
draw("重さで見せます。", x: 68, y: 300, size: 78, weight: .black, color: ink, tracking: -3)
draw("消せるものを塊にして積み、レバーを引くと瓶へ。", x: 72, y: 250, size: 22, weight: .regular, color: ink)
draw("7日間は掴んで戻せます。", x: 72, y: 214, size: 22, weight: .regular, color: ink)

// ブランド
ink.setFill()
rounded(NSRect(x: 80, y: 84, width: 56, height: 56), 16).fill()
grape.setFill()
rounded(NSRect(x: 72, y: 92, width: 56, height: 56), 16).fill()
ink.setStroke()
let mark = rounded(NSRect(x: 72, y: 92, width: 56, height: 56), 16)
mark.lineWidth = 5
mark.stroke()
draw("disclean", x: 146, y: 116, size: 34, weight: .black, color: ink, tracking: -1)
draw("ディスクリン", x: 148, y: 92, size: 17, weight: .regular, color: ink)

// 塊のタワー（実測値の比率）
let towerX: CGFloat = 760
let towerW: CGFloat = 372
chunk(NSRect(x: towerX, y: 300, width: towerW, height: 196), fill: lime)
chunk(NSRect(x: towerX, y: 218, width: towerW, height: 72), fill: sunbeam)
chunk(NSRect(x: towerX, y: 150, width: towerW, height: 58), fill: sky)
draw("71.5 GB", x: towerX + 28, y: 400, size: 46, weight: .bold, color: ink, mono: true)
draw("使っていない iOS シミュレータ", x: towerX + 28, y: 348, size: 20, weight: .regular, color: ink)
draw("26.6 GB", x: towerX + 28, y: 240, size: 30, weight: .bold, color: ink, mono: true)
draw("10.0 GB", x: towerX + 28, y: 168, size: 26, weight: .bold, color: ink, mono: true)
draw("実測 2026-08-20 / MacBook M4", x: towerX + 4, y: 108, size: 16, weight: .regular, color: ink, mono: true)

NSGraphicsContext.restoreGraphicsState()
if let data = rep.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
