// PhloxCore — Domain 層（E1-1 骨組み）。
//
// AgentDomain（sibling Phlox の共有パッケージ）を再エクスポートし、PhloxCore を import した
// モジュールが SessionStatus / AgentKind 等の SSOT 型へ追加 import なしでアクセスできるようにする。
// iOS 集約モデル（Session / Approval / ApprovalDecision / ConnectionConfig）と Repository /
// TokenStore / Authenticating 等のプロトコルは E1-2 / E1-3 以降で追加する。
@_exported import AgentDomain
import Foundation

/// PhloxCore モジュールのバージョン情報。骨組みが正しく解決・コンパイルされることの確認用。
public enum PhloxCore {
    /// 共有 AgentDomain が iOS ターゲットから利用可能であることを示す（Architecture Y の検証点）。
    public static let supportedAgentKinds: [AgentKind] = AgentKind.allCases
}
