import DiscleanKit
import SwiftUI

/// S-38 システムデータの中身。macOS の「システムデータ」がなぜ大きいのかを、消さずに見せる。
///
/// ここに並ぶものの多くは、ディスクリンが消してはいけないもの。だから「消さない理由」と
/// 「自分でどう減らせるか」を、量と同じ重さで書く。片づけられるのはシミュレータ本体だけで、
/// それは上の一覧（ルール）に出る。
struct SystemDataSection: View {
    @Environment(\.colorScheme) private var scheme
    let model: AppModel

    var body: some View {
        let surface = Surface(scheme: scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text("システムデータの中身")
                .font(Tokens.display(28))
                .foregroundStyle(surface.text)
            Text("macOS が「システムデータ」とまとめて出している量の内わけを測ります。**消しません**。減らし方も一緒に出します。")
                .font(Tokens.body(13))
                .foregroundStyle(surface.text)
                .fixedSize(horizontal: false, vertical: true)

            if model.systemDataMeasuring {
                BusyBoard(busy: model.busy, onStop: { model.stopWork() })
            } else {
                Button(model.systemData == nil ? "システムデータをしらべる" : "もう一度しらべる") {
                    Task { await model.findSystemData() }
                }
                .buttonStyle(CandyButtonStyle(fill: Tokens.sky))
            }

            if let result = model.systemData, !model.systemDataMeasuring {
                if result.interrupted {
                    Text("途中でやめました。測れたぶんだけを出しています。")
                        .font(Tokens.bodyBold(13))
                        .foregroundStyle(surface.text)
                }
                ForEach(Array(result.items.enumerated()), id: \.element.kind) { index, item in
                    SystemDataCard(item: item)
                        .plopIn(index: index)
                }
                if result.blocked {
                    Text("読めない場所がありました。フルディスクアクセスを付けると測れます。")
                        .font(Tokens.body(12))
                        .foregroundStyle(surface.text)
                }
                Text("ディスクリンが片づけられるのは、このうちシミュレータ本体だけです。上の一覧に出ます。")
                    .font(Tokens.body(12))
                    .foregroundStyle(surface.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }
}

/// システムデータ 1 項目。量・何か・消さない理由・減らし方を 1 枚に載せる。
struct SystemDataCard: View {
    let item: SystemDataItem

    var body: some View {
        HardCard(fill: item.state == .measured ? Tokens.paper : Tokens.paper.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(sizeText)
                        .font(Tokens.weightedData(20, bytes: item.bytes ?? 0))
                    Text(item.text.title)
                        .font(Tokens.bodyBold(15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(item.text.whatItIs)
                    .font(Tokens.body(12))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(item.details, id: \.self) { line in
                    Text("・" + line)
                        .font(Tokens.data(11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 安全に関わる理由は装飾しない（§1.3）。
                Text("消さない理由: " + item.text.whyNotDeleted)
                    .font(Tokens.body(12))
                    .fixedSize(horizontal: false, vertical: true)
                Text("減らしかた: " + item.text.howToReduce)
                    .font(Tokens.bodyBold(12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Tokens.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// 量が分からないときは、0 と混同させない言葉にする（§1.2）。
    private var sizeText: String {
        switch item.state {
        case .measured: Format.bytes(item.bytes ?? 0)
        case .absent: "なし"
        case .blocked: "読めません"
        case .unknown: "不明"
        }
    }
}
