// アプリアイコンを描く（HEAVY CANDY: ライムの塊 + 黒キーライン + ぼかし 0 の影）。
// 使い方: swift tools/icon/render-icon.swift <出力先ディレクトリ>
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

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

func render(size: Int) -> Data? {
    let scale = CGFloat(size) / 1024
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    // 角丸の地（macOS のアイコン枠に収まるよう内側にマージンを取る）
    let margin: CGFloat = 96 * scale
    let plate = NSRect(
        x: margin, y: margin, width: CGFloat(size) - margin * 2, height: CGFloat(size) - margin * 2)
    paper.setFill()
    rounded(plate, 200 * scale).fill()
    ink.setStroke()
    let plateStroke = rounded(plate, 200 * scale)
    plateStroke.lineWidth = 26 * scale
    plateStroke.stroke()

    // 積んだ塊（下ほど大きい = 容量に比例する高さ）
    let chunkWidth = plate.width * 0.62
    let x = plate.midX - chunkWidth / 2
    let heights: [CGFloat] = [0.30, 0.20, 0.13]
    let fills = [lime, lime, sunbeam]
    var y = plate.minY + plate.height * 0.14
    for (index, ratio) in heights.enumerated() {
        let height = plate.height * ratio
        let rect = NSRect(x: x, y: y, width: chunkWidth, height: height)
        // ぼかし 0 のハードオフセット影
        ink.setFill()
        rounded(rect.offsetBy(dx: 20 * scale, dy: -20 * scale), 44 * scale).fill()
        fills[index].setFill()
        rounded(rect, 44 * scale).fill()
        ink.setStroke()
        let stroke = rounded(rect, 44 * scale)
        stroke.lineWidth = 22 * scale
        stroke.stroke()
        y += height + plate.height * 0.045
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let data = render(size: size) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
}
print("wrote icons to \(outDir)")
