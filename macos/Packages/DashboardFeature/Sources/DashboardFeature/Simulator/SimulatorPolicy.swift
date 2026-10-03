import SimulatorBridgeKit

/// 実行記録で確認した組だけを許可する。範囲指定や永続化した例外は持たない。
struct SimulatorPolicy {
    struct Entry: Equatable {
        let xcodeBuild: String
        let runtimeIdentifier: String
        let supportsInput: Bool
    }

    enum Support: Equatable {
        case unsupported
        case displayOnly
        case supported
        case unverified

        var allowsDisplay: Bool { self != .unsupported }
        var allowsInput: Bool { self == .supported || self == .unverified }
        var message: String? {
            switch self {
            case .unsupported: "未確認の組み合わせです"
            case .displayOnly: "表示のみ対応しています。入力は送信できません"
            case .unverified: "未確認の組み合わせで実行中（このタブのみ）"
            case .supported: nil
            }
        }
    }

    // 関門・S5・S6 の正式記録: simulator-compatibility-verification.md。
    static let verified = SimulatorPolicy(entries: [
        Entry(xcodeBuild: "17C52", runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-2",
              supportsInput: true),
    ])
    let entries: [Entry]

    func support(xcodeBuild: String, runtimeIdentifier: String, triesUnverified: Bool) -> Support {
        if let entry = entries.first(where: { $0.xcodeBuild == xcodeBuild && $0.runtimeIdentifier == runtimeIdentifier }) {
            return entry.supportsInput ? .supported : .displayOnly
        }
        return triesUnverified ? .unverified : .unsupported
    }
}
