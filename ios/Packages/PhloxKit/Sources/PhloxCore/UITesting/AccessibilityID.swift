import Foundation

/// XCUITest が参照する `accessibilityIdentifier` の単一真実源。
public enum AccessibilityID {
    public static let sessionList = "sessionList"
    public static let spawnButton = "spawnButton"
    public static let spawnCreateButton = "spawnCreateButton"
    public static let launchGateUnlock = "launchGateUnlock"

    public static func sessionRow(_ id: String) -> String { "sessionRow.\(id)" }
    public static func attentionRow(_ id: String) -> String { "attentionRow.\(id)" }
    public static let approvalAccept = "approvalAccept"
    public static let sessionDetail = "sessionDetail"
    public static let chatAnswer = "chatAnswer"
    public static let unreachableCard = "unreachableCard"
}
