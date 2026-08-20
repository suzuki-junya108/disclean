import DiscleanKit
import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var model = AppModel()

    var body: some View {
        let surface = Surface(scheme: scheme)
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
                .background(surface.background)
            Divider().overlay(surface.keyline)
            ZStack(alignment: .top) {
                surface.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if let message = model.errorMessage {
                        ErrorBannerView(message: message) { model.errorMessage = nil }
                    }
                    if model.needsPermissionGuide && model.section == .clean {
                        PermissionGuideView(model: model)
                    }
                    detail
                }
                .padding(24)
            }
        }
        .background(surface.background)
        .task { await model.scan() }
        .sheet(isPresented: Binding(get: { model.showConfirmSheet }, set: { model.showConfirmSheet = $0 })) {
            ConfirmSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { model.showUpdateSheet }, set: { model.showUpdateSheet = $0 })) {
            UpdateSheet(model: model)
        }
    }

    /// 自前のサイドバー。HEAVY CANDY のピルで、選択中が一目で分かるようにする。
    private var sidebar: some View {
        let surface = Surface(scheme: scheme)
        return VStack(alignment: .leading, spacing: 10) {
            Text("ディスクリン")
                .font(Tokens.display(20))
                .foregroundStyle(surface.text)
                .padding(.bottom, 8)
            ForEach(AppModel.Section.allCases) { section in
                Button {
                    model.section = section
                } label: {
                    HStack {
                        Text(section.title)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(
                    CandyButtonStyle(fill: model.section == section ? Tokens.lime : surface.card)
                )
                .accessibilityAddTraits(model.section == section ? [.isSelected] : [])
            }
            Spacer()
            if let report = model.doctorReport {
                Text("カタログ \(report.appliedCatalogVersion)")
                    .font(Tokens.data(10))
                    .foregroundStyle(surface.text)
            }
            Text("v" + DiscleanVersion.current)
                .font(Tokens.data(10))
                .foregroundStyle(surface.text)
        }
        .padding(18)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .clean:
            switch model.phase {
            case .scanning: ScanningView(model: model)
            case .results: ResultListView(model: model)
            case .applying: ApplyProgressView()
            case .done: CompletionSummaryView(model: model)
            }
        case .quarantine: QuarantineView(model: model)
        case .history: HistoryView(model: model)
        case .settings: SettingsView(model: model)
        }
    }
}

struct ErrorBannerView: View {
    @Environment(\.colorScheme) private var scheme
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(message)
                .font(Tokens.body(14))
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("閉じる", action: onDismiss)
                .buttonStyle(CandyButtonStyle(fill: Tokens.paper))
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .fill(Surface(scheme: scheme).keyline)
                    .offset(x: Tokens.chipShadowOffset, y: Tokens.chipShadowOffset)
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous).fill(Tokens.tomato)
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .strokeBorder(Surface(scheme: scheme).keyline, lineWidth: Tokens.keylineWidth)
            }
        )
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }
}

/// キャンディ色のボタン。明色の上は必ず ink（§2.2）。
struct CandyButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    var fill: Color = Tokens.lime
    var textColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        let surface = Surface(scheme: scheme)
        configuration.label
            .font(Tokens.bodyBold(14))
            .foregroundStyle(textColor ?? Tokens.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule().fill(surface.keyline)
                        .offset(
                            x: configuration.isPressed ? 1 : Tokens.chipShadowOffset,
                            y: configuration.isPressed ? 1 : Tokens.chipShadowOffset)
                    Capsule().fill(fill)
                    Capsule().strokeBorder(surface.keyline, lineWidth: Tokens.keylineWidth)
                }
            )
    }
}
