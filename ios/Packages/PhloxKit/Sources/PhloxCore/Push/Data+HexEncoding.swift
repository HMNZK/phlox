import Foundation

public extension Data {
    /// 各バイトを2桁の小文字16進で連結した文字列（APNs デバイストークンの wire 形式）。
    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
