import SwiftUI

/// 待たされている間に必ず出る板。
///
/// 「何をしているのか」「どこまで進んだのか」「いま触っているのはどれか」
/// 「終わったものは何か」「この間なにが起きないか」を 1 枚で見せる。
/// 待ち時間の表現をここに 1 つだけ置き、画面ごとに作らない。
struct BusyBoard: View {
    @Environment(\.colorScheme) private var scheme
    let busy: BusyState

    var body: some View {
        let surface = Surface(scheme: scheme)
        if let job = busy.job {
            HardCard(fill: surface.card) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(job.title)
                            .font(Tokens.display(38))
                            .foregroundStyle(surface.text)
                        WorkingDots(accent: job.accent)
                        Spacer(minLength: 0)
                        Text(countText)
                            .font(Tokens.data(13))
                            .foregroundStyle(surface.text)
                            .contentTransition(.numericText())
                            .animation(Motion.gummy, value: busy.completed)
                    }

                    GummyBar(fraction: busy.fraction, accent: job.accent)

                    // いま何をしているか。数字だけにしない。
                    Text(busy.stepLabel)
                        .font(Tokens.bodyBold(15))
                        .foregroundStyle(surface.text)

                    // いま触っているもの 1 件。
                    HStack(spacing: 8) {
                        Text("▶")
                            .font(Tokens.data(12))
                            .foregroundStyle(job.accent)
                        Text(busy.current.isEmpty ? "準備しています" : busy.current)
                            .font(Tokens.data(12))
                            .foregroundStyle(surface.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .jelly(on: busy.current, strength: 0.05)
                    }
                    .animation(Motion.gummy, value: busy.current)

                    // 終わったものが下に積まれていく（何をやったかが残る）。
                    if !busy.recent.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(busy.recent.enumerated()), id: \.element.id) { offset, line in
                                HStack(spacing: 8) {
                                    Text("✓")
                                        .font(Tokens.data(11))
                                    Text(line.text)
                                        .font(Tokens.data(11))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundStyle(surface.text)
                                .opacity(max(0.18, 0.62 - Double(offset) * 0.14))
                            }
                        }
                        .transition(.opacity)
                    }

                    Text(job.note)
                        .font(Tokens.body(12))
                        .foregroundStyle(surface.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(job.title)。\(busy.stepLabel)。\(countText)")
        }
    }

    /// 件数の言い方。総数が分かるまでは「数えています」と正直に書く。
    private var countText: String {
        guard busy.total > 0 else {
            return busy.completed > 0 ? "\(busy.completed) 件おわり" : "数えています"
        }
        let percent = Int((busy.fraction ?? 0) * 100)
        return "\(busy.completed) / \(busy.total) 件  \(percent)%"
    }
}

/// 進みぐあいのゲージ。重いグミが伸びるように、行き過ぎてから収まる。
/// 総数が分からないときは、塊が往復して「止まっていない」ことだけを示す。
struct GummyBar: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double?
    let accent: Color

    @State private var sliding = false

    private let height: CGFloat = 26

    var body: some View {
        let surface = Surface(scheme: scheme)
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(surface.background)
                if let fraction {
                    Capsule()
                        .fill(accent)
                        .frame(width: max(height, width * fraction))
                        .animation(reduceMotion ? .default : Motion.gummy, value: fraction)
                } else if reduceMotion {
                    // 動きを減らす設定では往復させない。進行中であることは文字で伝える。
                    Capsule()
                        .fill(accent.opacity(0.5))
                        .frame(width: width)
                } else {
                    Capsule()
                        .fill(accent)
                        .frame(width: width * 0.34)
                        .offset(x: sliding ? width * 0.66 : 0)
                        .animation(
                            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                            value: sliding
                        )
                        .onAppear { sliding = true }
                }
                Capsule()
                    .strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 3 つの玉が順に跳ねる。「まだ動いている」ことを、回るカーソルの代わりに見せる。
struct WorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accent: Color

    @State private var bouncing = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                    .offset(y: bouncing ? -5 : 3)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.42)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12),
                        value: bouncing)
            }
        }
        .onAppear { bouncing = true }
        .accessibilityHidden(true)
    }
}

extension View {
    /// 画面のどこから始めた作業でも、同じ板が同じ場所に出るようにする。
    func busyOverlay(_ busy: BusyState) -> some View {
        overlay {
            if busy.isRunning && busy.coversScreen {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    BusyBoard(busy: busy)
                        .frame(maxWidth: 560)
                        .padding(30)
                        .plopIn()
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.gummy, value: busy.isRunning)
    }
}
