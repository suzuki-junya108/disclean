import SwiftUI

/// ウニョウニョ担当（アプリ側）。LP と同じ動きの語彙をここに置く。
///
/// 決まりごと:
/// - 常時ゆれるのは**飾り層だけ**。押せるものの当たり判定は動かさない
/// - 30fps の刻みで動かす（常時 60fps で塗り直さない）
/// - `accessibilityReduceMotion` のときは、いっさい動かさない

/// 1 つ押したときに、隣へ伝える波。
struct ChainPulse: Equatable {
    let index: Int
    let token: Int
    let strength: CGFloat

    static func == (lhs: ChainPulse, rhs: ChainPulse) -> Bool {
        lhs.token == rhs.token
    }
}

/// 常時ゆらぐ飾り層。中身は触れない（当たり判定を持たない）。
struct WobbleLayer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var amplitude: CGFloat = 0.008
    var speed: Double = 1
    var seed: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate * speed + seed
                content
                    .scaleEffect(
                        x: 1 + CGFloat(sin(time * 1.1)) * amplitude,
                        y: 1 + CGFloat(sin(time * 1.37 + 1.2)) * amplitude,
                        anchor: .center
                    )
                    .rotationEffect(.degrees(Double(sin(time * 0.83)) * Double(amplitude) * 34))
            }
        }
    }
}

/// 波が届いたら、遅れて潰れて戻る。
private struct ChainWobble: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let pulse: ChainPulse?

    @State private var squash: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 + squash * 0.9, y: 1 - squash, anchor: .center)
            .onChange(of: pulse) {
                guard !reduceMotion, let pulse else { return }
                let distance = abs(index - pulse.index)
                guard distance <= 4 else { return }
                let attenuated = pulse.strength * pow(0.55, CGFloat(distance))
                let delay = Double(distance) * 0.055
                withAnimation(.easeOut(duration: 0.08).delay(delay)) { squash = attenuated }
                withAnimation(Motion.squishy.delay(delay + 0.08)) { squash = 0 }
            }
    }
}

/// 溶けて融合する塊の集まり。隔離庫の中身を「ひとつの塊」として見せる。
///
/// `Canvas` の中でぼかしたうえで α のしきい値を切ると、近い円どうしが 1 つにつながる
/// （いわゆるメタボール）。`blur` + `contrast` で作ると色がにじむため、こちらを使う。
struct GooeyBlobs: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 分量（バイト）。大きいものから 6 個まで描く。
    let amounts: [Int64]
    var tint: Color = Tokens.lime
    var height: CGFloat = 78

    private var blobs: [CGFloat] {
        let top = Array(amounts.prefix(6))
        guard let largest = top.max(), largest > 0 else { return [] }
        return top.map { bytes in
            let ratio = CGFloat(Double(bytes) / Double(largest))
            return max(0.42, 0.42 + ratio * 0.5)  // 直径の比（高さに対する割合）
        }
    }

    var body: some View {
        let surface = Surface(scheme: scheme)
        let sizes = blobs
        if sizes.isEmpty {
            EmptyView()
        } else if reduceMotion {
            canvas(sizes: sizes, keyline: surface.keyline, phase: 0)
                .frame(height: height)
                .accessibilityHidden(true)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                canvas(
                    sizes: sizes, keyline: surface.keyline,
                    phase: timeline.date.timeIntervalSinceReferenceDate)
            }
            .frame(height: height)
            .accessibilityHidden(true)
        }
    }

    /// 1 枚ぶんの描き方。輪郭は、太らせた黒い塊を下に敷いて作る（キーラインの代わり）。
    private struct Pass {
        let color: Color
        let grow: CGFloat
    }

    private func canvas(sizes: [CGFloat], keyline: Color, phase: Double) -> some View {
        Canvas { context, size in
            for pass in [Pass(color: keyline, grow: 3), Pass(color: tint, grow: 0)] {
                draw(in: &context, size: size, sizes: sizes, pass: pass, phase: phase)
            }
        }
    }

    private func draw(
        in context: inout GraphicsContext, size: CGSize, sizes: [CGFloat],
        pass: Pass, phase: Double
    ) {
        context.drawLayer { layer in
            layer.addFilter(.alphaThreshold(min: 0.5, color: pass.color))
            layer.addFilter(.blur(radius: 8))
            layer.drawLayer { blobLayer in
                // 端が切れないよう、左右に半径ぶんの余白を残して並べる
                let margin = size.height * 0.5
                let span = max(0, size.width - margin * 2)
                let step = sizes.count > 1 ? span / CGFloat(sizes.count - 1) : 0
                for (index, ratio) in sizes.enumerated() {
                    // 大きさは分量、揺れは位置ごとにずらした正弦波
                    let wobble = phase == 0 ? 0 : sin(phase * 1.3 + Double(index)) * 0.04
                    let diameter = size.height * (ratio + CGFloat(wobble)) + pass.grow * 2
                    let x = margin + step * CGFloat(index)
                    let y = size.height * 0.5
                    let rect = CGRect(
                        x: x - diameter / 2, y: y - diameter / 2,
                        width: diameter, height: diameter)
                    blobLayer.fill(Circle().path(in: rect), with: .color(.white))
                }
            }
        }
    }
}

extension View {
    /// 隣から届いた波で揺れる。
    func chainWobble(index: Int, pulse: ChainPulse?) -> some View {
        modifier(ChainWobble(index: index, pulse: pulse))
    }
}
