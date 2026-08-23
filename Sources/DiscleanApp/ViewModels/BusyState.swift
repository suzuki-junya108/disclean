import DiscleanKit
import Foundation
import Observation
import SwiftUI

/// 「いま、なにをしているか」を 1 か所で持つ。
///
/// このアプリで待たされる場面（しらべる・うつす・けす・もどす）は、
/// すべてこの状態を通して同じ板（`BusyBoard`）で描く。
/// マウスカーソルが回っているだけで中身が分からない、という状態を作らないための土台。
@MainActor
@Observable
final class BusyState {
    /// 終わったものを下に積んでいくときの 1 行。
    struct Line: Identifiable {
        let id: Int
        let text: String
    }

    /// 走っている作業の種類。見出しの言葉と色をここで決める（画面ごとに変えない）。
    enum Job {
        case scanning
        case applying
        case deleting
        case restoring

        /// 大見出し。動詞で、いま起きていることだけを言う。
        var title: String {
            switch self {
            case .scanning: "しらべています"
            case .applying: "うつしています"
            case .deleting: "けしています"
            case .restoring: "もどしています"
            }
        }

        /// 見出しの下の 1 行。「この間なにが起きないか」を書く。
        var note: String {
            switch self {
            case .scanning: "読み取りだけを行います。この間、何も消えません。"
            case .applying: "同じディスクの中で移しています。まだ消えていません。あとで戻せます。"
            case .deleting: "隔離庫から完全に消しています。これは元に戻せません。"
            case .restoring: "隔離庫から元の場所へ戻しています。"
            }
        }

        var accent: Color {
            switch self {
            case .scanning: Tokens.sky
            case .applying: Tokens.lime
            case .deleting: Tokens.tomato
            case .restoring: Tokens.sunbeam
            }
        }
    }

    private(set) var job: Job?
    /// 画面全体を覆って見せるか（片づけ画面のように、その場に出せるときは false）。
    private(set) var coversScreen = false
    private(set) var stepLabel = "はじめています"
    private(set) var current = ""
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var bytes: Int64 = 0
    private(set) var recent: [Line] = []

    private var lineSeed = 0
    private var home = ""

    var isRunning: Bool { job != nil }

    /// 0.0〜1.0。総数がまだ分からないときは nil（往復する不定表示にする）。
    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }

    /// 作業を始める。`coversScreen` が true のときは画面全体を覆って出す。
    func begin(_ job: Job, home: String, coversScreen: Bool = false) {
        self.job = job
        self.home = home
        self.coversScreen = coversScreen
        stepLabel = "はじめています"
        current = ""
        completed = 0
        total = 0
        bytes = 0
        recent = []
    }

    /// 1 件分の報せを受け取る。終わったものは下に積んでいく。
    func update(_ progress: WorkProgress) {
        stepLabel = Self.label(for: progress.step)
        completed = progress.completed
        total = progress.total
        bytes += progress.bytes

        let shown = progress.path.isEmpty ? "" : ScanItemFormat.shortPath(progress.path, home: home)
        guard shown != current else { return }
        if !current.isEmpty {
            lineSeed += 1
            recent.insert(Line(id: lineSeed, text: current), at: 0)
            if recent.count > 4 { recent.removeLast() }
        }
        current = shown
    }

    /// 作業を終える。板は消える。
    func end() {
        job = nil
        current = ""
        recent = []
    }

    /// 進みぐあいの言葉。数字だけでは何をしているか分からないので必ず添える。
    private static func label(for step: WorkProgress.Step) -> String {
        switch step {
        case .counting: "何件あるか数えています"
        case .measuring: "大きさを測っています"
        case .moving: "隔離庫へ移しています"
        case .deleting: "完全に削除しています"
        case .restoring: "元の場所へ戻しています"
        case .running: "外部ツールを動かしています"
        }
    }
}
