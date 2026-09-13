import Foundation

/// Kit の中で人向けの文を組み立てるときのバイト表記（1000 進）。
/// CLI の `Output.bytes` と同じ規則にそろえる（0 を "Zero KB" と書かせない）。
public enum ByteText {
    public static func string(_ value: Int64) -> String {
        if value <= 0 { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: value)
    }
}
