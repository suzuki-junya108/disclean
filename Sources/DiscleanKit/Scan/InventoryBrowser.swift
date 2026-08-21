import Foundation
import Observation

/// 「なかみ」を 1 段ずつ辿るための状態。画面（GUI）と切り離してあるので、
/// 開く・戻るの挙動をそのままテストできる。
///
/// 画面は 1 段ずつ開く。全部を平らに並べると数万行になって、かえって何も分からない。
@MainActor
@Observable
public final class InspectSession {
    /// 開ける場所 1 つ。隔離庫の場合、実体（`path`）と元の場所（`label`）が違う。
    public struct Root: Identifiable, Equatable {
        public let path: String
        public let label: String
        public let note: String?
        /// フォルダなら中を開ける。ファイルはそれ自身が中身。
        public let isDirectory: Bool
        public var bytes: Int64?
        public var fileCount: Int?

        public var id: String { path }

        public init(
            path: String, label: String, note: String? = nil, isDirectory: Bool = true,
            bytes: Int64? = nil, fileCount: Int? = nil
        ) {
            self.path = path
            self.label = label
            self.note = note
            self.isDirectory = isDirectory
            self.bytes = bytes
            self.fileCount = fileCount
        }
    }

    /// パンくず 1 段。
    public struct Crumb: Identifiable, Equatable {
        public let name: String
        public let path: String
        public var id: String { path }
    }

    public let title: String
    /// この項目は何か。ふつうの言葉で 1〜2 文。
    public let whatItIs: String
    /// 実行する（または戻す）と何が起きるか。
    public let fate: String
    public let undoable: Bool
    /// 隔離庫の run を見ているときだけ入る。
    public let runId: String?

    public private(set) var roots: [Root]
    public private(set) var trail: [Crumb] = []
    public private(set) var inventory: Inventory?
    public private(set) var loading = false

    private var loadToken = 0
    /// いま走っている読み取り。テストと「閉じる」で待ち合わせるために持つ。
    private var pending: Task<Void, Never>?

    /// 読み取りが終わるまで待つ（テスト用）。
    public func waitForPendingWork() async {
        await pending?.value
    }

    public init(
        title: String, whatItIs: String, fate: String, undoable: Bool, runId: String? = nil,
        roots: [Root]
    ) {
        self.title = title
        self.whatItIs = whatItIs
        self.fate = fate
        self.undoable = undoable
        self.runId = runId
        self.roots = roots
    }

    /// いま見ている場所。根が 1 つならそこから、複数なら選んだあとから中身を出す。
    public var currentPath: String? {
        if let last = trail.last { return last.path }
        if roots.count == 1 { return roots[0].path }
        return nil
    }

    /// 根の一覧を出す段にいるか。
    public var showsRootList: Bool { currentPath == nil && !roots.isEmpty }

    public var isEmptyTarget: Bool { roots.isEmpty }

    /// 画面上部に出す「いまどこを見ているか」。
    public var locationLabel: String {
        if let last = trail.last { return last.path }
        if roots.count == 1 { return roots[0].label }
        return ""
    }

    public func start() {
        if roots.count == 1 {
            load()
        } else {
            measureRoots()
        }
    }

    public func open(_ root: Root) {
        trail = [Crumb(name: root.label, path: root.path)]
        load()
    }

    public func open(_ entry: InventoryEntry) {
        guard entry.isDirectory else { return }
        trail.append(Crumb(name: entry.name, path: entry.path))
        load()
    }

    /// パンくずの途中に戻る。`index` が nil なら根まで戻る。
    public func back(to index: Int? = nil) {
        if let index, index < trail.count {
            trail = Array(trail.prefix(index + 1))
        } else {
            trail = []
        }
        if currentPath == nil {
            inventory = nil
            measureRoots()
        } else {
            load()
        }
    }

    public var canGoBack: Bool { !trail.isEmpty }

    private func load() {
        guard let path = currentPath else { return }
        loadToken += 1
        let token = loadToken
        loading = true
        pending = Task.detached(priority: .userInitiated) {
            let listed = FileInventory.list(paths: [path], limit: 60)
            await MainActor.run { [weak self] in
                guard let self, token == self.loadToken else { return }
                self.inventory = listed
                self.loading = false
            }
        }
    }

    /// 根が複数あるときは、それぞれの大きさを測って一覧にする。
    private func measureRoots() {
        guard roots.contains(where: { $0.bytes == nil || $0.fileCount == nil }) else { return }
        let paths = roots.map(\.path)
        loading = true
        pending = Task.detached(priority: .userInitiated) {
            let measured = paths.map { path in
                let listed = FileInventory.list(paths: [path], limit: 1)
                return (path, listed.totalBytes, listed.totalFiles)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (path, bytes, files) in measured {
                    guard let index = self.roots.firstIndex(where: { $0.path == path }) else { continue }
                    self.roots[index].bytes = bytes
                    self.roots[index].fileCount = files
                }
                self.loading = false
            }
        }
    }
}
