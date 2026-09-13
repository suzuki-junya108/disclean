import AppKit
import DiscleanKit
import Foundation
import SwiftUI

#if UI_PREVIEW
    /// 画面確認用の入口。このファイルは `--preview` ビルドにしか含まれない（配布物には入らない）。
    extension AppModel {
        /// `DISCLEAN_PREVIEW` で指定された画面を起動直後に開く。
        func applyPreviewScenario() {
            guard let scenario = ProcessInfo.processInfo.environment["DISCLEAN_PREVIEW"] else { return }
            if scenario == "quarantine" {
                section = .quarantine
                refreshQuarantine()
            } else if scenario == "inspect-run" {
                section = .quarantine
                refreshQuarantine()
                if let run = quarantineRuns.first { inspect(run: run) }
            } else if scenario == "done" {
                Task { await apply() }
            } else if scenario == "confirm" {
                showConfirmSheet = true
            } else if scenario == "big" {
                section = .big
                Task { await findBigItems() }
            } else if scenario == "busy" {
                Task { await showBusyBoardPreview() }
            } else if scenario == "system" {
                Task { await findSystemData() }
            } else if scenario == "system-card" {
                // 一覧の下にある欄を、スクロールせずに撮れるよう単独の窓に出す。
                showPreviewWindow(SystemDataSection(model: self))
                Task { await findSystemData() }
            } else if scenario == "confirm-card" {
                // シートは窓として撮れないことがあるため、同じ中身を単独の窓に出す。
                showPreviewWindow(ConfirmSheet(model: self))
            } else if scenario.hasPrefix("inspect-rule:") {
                let ruleId = String(scenario.dropFirst("inspect-rule:".count))
                if let item = scanResult?.items.first(where: { $0.ruleId == ruleId }) {
                    inspect(item: item)
                }
            }
        }

        /// 確認したい画面だけを載せた窓を開き、撮影用に窓番号を標準出力へ書く。
        private func showPreviewWindow(_ content: some View) {
            // 縁なしの窓は画面の高さに縮められないので、下の欄まで 1 枚に収まる。
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 2000),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreviewHost(content: content))
            window.setFrameTopLeftPoint(NSPoint(x: 60, y: (NSScreen.main?.visibleFrame.maxY ?? 1000)))
            window.orderFront(nil)
            PreviewWindows.keep.append(window)
            print("preview-window \(window.windowNumber)")
            fflush(stdout)
        }

        /// 作業中の板を、実際の処理を待たずにゆっくり流して見せる。
        private func showBusyBoardPreview() async {
            let places = [
                "\(env.home)/Library/Caches/com.apple.dt.Xcode/DerivedData/App-abc/Build/Intermediates",
                "\(env.home)/Library/Developer/CoreSimulator/Devices/DEV-1/data/Library/Caches",
                "\(env.home)/.cache/uv/wheels/cp313/numpy-2.1.0.whl",
                "\(env.home)/Library/Caches/Homebrew/downloads/ffmpeg-7.1.tar.gz",
                "\(env.home)/.npm/_cacache/content-v2/sha512/ab/cd",
            ]
            busy.begin(.deleting, home: env.home, coversScreen: true)
            for (index, place) in places.enumerated() {
                busy.update(
                    WorkProgress(
                        step: .deleting, ruleId: "preview", path: place,
                        completed: index, total: places.count, bytes: 1_400_000_000))
                try? await Task.sleep(for: .seconds(1.4))
            }
        }
    }

    /// 開いた確認用の窓を、閉じるまで手放さないための置き場。
    @MainActor
    private enum PreviewWindows {
        static var keep: [NSWindow] = []
    }

    /// 本番の画面と同じ地の色に載せる。
    private struct PreviewHost<Content: View>: View {
        @Environment(\.colorScheme) private var scheme
        let content: Content

        var body: some View {
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Surface(scheme: scheme).background)
        }
    }
#endif
