/// Mac と iOS で共通の使用量表示と保存キー。
public enum UsageBarStyle: String, CaseIterable, Sendable {
    case bar
    case percent

    public static let defaultsKey = "phlox.usage.bottomBarStyle"
}
