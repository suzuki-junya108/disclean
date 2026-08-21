import Foundation

/// ルールが対象とする実際のパスを決める。
///
/// スキャンと実行が必ず同じ結果を使うよう、解決の手順をここ 1 箇所に置く。
/// 別々に解決すると、見せた場所と動かす場所がずれる。
public enum RulePaths {
    /// 解決したパス。ツールに聞く場合は実行を伴うため、結果を持ち回れるようにする。
    public struct Resolved: Sendable, Equatable {
        public let paths: [String]
        /// ツールに聞いたが答えが得られなかった（未導入・エラー）。
        public let toolUnavailable: Bool
        /// ツールが答えた場所が、触ってよい範囲の外だった。
        public let rejected: [String]
    }

    /// - Parameter guardian: ツールが答えた場所を検証する。答えを無条件には信じない。
    public static func resolve(
        _ rule: Rule, home: String, guardian: PathGuard, timeoutSeconds: Int = 10
    ) -> Resolved {
        guard let pathsFrom = rule.pathsFrom else {
            let listed = (rule.paths ?? []).map { PathGuard.normalize(Expand.tilde($0, home: home)) }
            return Resolved(paths: listed, toolUnavailable: false, rejected: [])
        }

        let result = CommandRunner.run(pathsFrom.command, timeoutSeconds: timeoutSeconds)
        guard result.succeeded else {
            return Resolved(paths: [], toolUnavailable: true, rejected: [])
        }
        let head =
            result.standardOutput
            .split(separator: "\n").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let base = Expand.tilde(head, home: home)
        guard base.hasPrefix("/") else {
            return Resolved(paths: [], toolUnavailable: true, rejected: [])
        }

        let targets =
            pathsFrom.subpaths.isEmpty
            ? [base]
            : pathsFrom.subpaths.map { base + "/" + $0 }

        // ツールの答えをそのままは使わない。同梱ルールと同じ規則で必ず検証する。
        var accepted: [String] = []
        var rejected: [String] = []
        for target in targets.map({ PathGuard.normalize($0) }) {
            if guardian.validateRulePath(target) == nil {
                accepted.append(target)
            } else {
                rejected.append(target)
            }
        }
        return Resolved(paths: accepted, toolUnavailable: false, rejected: rejected)
    }
}
