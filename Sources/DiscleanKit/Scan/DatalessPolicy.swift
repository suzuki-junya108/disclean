import Foundation

/// クラウド未ダウンロードファイル（dataless）の実体化を抑止する。
public enum DatalessPolicy {
    /// `stat.st_flags` に立つ dataless フラグ（Apple TN3150）。
    public static let sfDataless: UInt32 = 0x4000_0000

    private static let iopolTypeVFSMaterializeDatalessFiles: Int32 = 3
    private static let iopolScopeProcess: Int32 = 0
    private static let iopolMaterializeDatalessFilesOff: Int32 = 1

    /// プロセス起動直後に 1 回呼ぶ。失敗しても致命的ではない（走査は続行する）。
    @discardableResult
    public static func disableMaterialization() -> Bool {
        setiopolicy_np(
            iopolTypeVFSMaterializeDatalessFiles,
            iopolScopeProcess,
            iopolMaterializeDatalessFilesOff
        ) == 0
    }

    public static func isDataless(_ st: stat) -> Bool {
        (st.st_flags & sfDataless) != 0
    }
}
