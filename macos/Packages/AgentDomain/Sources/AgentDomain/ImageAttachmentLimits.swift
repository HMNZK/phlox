import Foundation

/// MBは10進。元画像と送信用画像の制限を区別する。
public enum ImageAttachmentLimits {
    public static let maxCount = 4
    public static let maxInputBytes = 20_000_000
    public static let maxTotalInputBytes = 80_000_000
    /// base64の4/3倍を含めて5MB以内（ClaudeのBedrock/Google Cloud経路の仕様）。
    public static let maxSendBytes = 5_000_000 / 4 * 3
    /// 旧iOSクライアントの4MiB画像も受信し、サーバー側で送信前に調整する。
    public static let maxWireBytes = 4 * 1024 * 1024
    public static let maxTotalSendBytes = maxCount * maxSendBytes
    public static let maxRequestBodyBytes = 24 * 1024 * 1024
    public static let inputSizeMessage = "画像は1枚あたり20MBまでです"
    public static let inputTotalMessage = "画像は合計80MBまでです"
    public static let countMessage = "画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。"
}
