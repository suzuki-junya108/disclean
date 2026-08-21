import SwiftUI

/// HEAVY CANDY の動き。塊は硬い箱ではなく、押せば潰れ、離せば行き過ぎて揺れて止まる
/// 重いグミとして振る舞う。「ギガバイトには重さがある」を動きでも言うための語彙。
///
/// すべて `accessibilityReduceMotion` で無効化できる（design-system D-06）。
enum Motion {
    /// 弾む。行き過ぎてから戻る。
    static let gummy = Animation.spring(response: 0.42, dampingFraction: 0.52)
    /// よく弾む。押した手応えを返すとき。
    static let squishy = Animation.spring(response: 0.34, dampingFraction: 0.42)
    /// 落ちる。重いものが着地するとき。
    static let drop = Animation.spring(response: 0.5, dampingFraction: 0.6)
    /// 触れたときの小さな反応。
    static let hover = Animation.easeOut(duration: 0.12)

    /// 積み上がるときの、1 つあたりの待ち時間。
    static func stagger(_ index: Int) -> Double { min(Double(index) * 0.06, 0.5) }
}

/// 状態が変わるたびに、一度だけ潰れて戻る。
private struct JellyOnChange<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    var strength: CGFloat = 0.08

    @State private var squash: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .center)
            .onChange(of: value) {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.09)) { squash = strength }
                withAnimation(Motion.squishy.delay(0.09)) { squash = 0 }
            }
    }
}

/// 押している間つぶれ、離すと揺れて戻る。
private struct GummyPress: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var strength: CGFloat = 0.04

    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: pressed ? 1 - strength : 1,
                y: pressed ? 1 + strength : 1,
                anchor: .center
            )
            .animation(reduceMotion ? nil : Motion.squishy, value: pressed)
            .onLongPressGesture(minimumDuration: 0, pressing: { pressed = $0 }, perform: {})
    }
}

/// 現れるときに、上から落ちて着地する。
private struct PlopIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int

    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: landed ? 1 : 0.9, y: landed ? 1 : 1.12, anchor: .bottom)
            .offset(y: landed ? 0 : -26)
            .opacity(landed ? 1 : 0)
            .onAppear {
                guard !reduceMotion else {
                    landed = true
                    return
                }
                withAnimation(Motion.drop.delay(Motion.stagger(index))) { landed = true }
            }
    }
}

extension View {
    /// 値が変わるたびに一度だけ揺れる。
    func jelly<Value: Equatable>(on value: Value, strength: CGFloat = 0.08) -> some View {
        modifier(JellyOnChange(value: value, strength: strength))
    }

    /// 押されている間つぶれる。
    func gummyPress(strength: CGFloat = 0.04) -> some View {
        modifier(GummyPress(strength: strength))
    }

    /// 上から落ちて着地する（`index` の順に少しずつ遅れる）。
    func plopIn(index: Int = 0) -> some View {
        modifier(PlopIn(index: index))
    }
}
