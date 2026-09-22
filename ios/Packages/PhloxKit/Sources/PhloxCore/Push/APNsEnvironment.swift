import Foundation

/// APNs 環境。実行バイナリに埋め込まれた `aps-environment` entitlement を実行時に読んで判定する。
/// ビルド構成（Debug/Release）と entitlement は独立に決まる（TestFlight は Release かつ development
/// entitlement）ため、判定材料にビルド構成（`#if DEBUG`）は使わない。
public enum APNsEnvironment: String, Sendable {
    case sandbox
    case production

    /// 現在の実行バイナリの `embedded.mobileprovision`（あれば）から判定する。
    /// プロファイルが無い、または `aps-environment` が読めない場合（App Store/TestFlight 配布、
    /// または Simulator・swift test ホスト）は、Simulator なら sandbox、それ以外は production に
    /// フォールバックする（Simulator の remote push トークンは sandbox でしか通らないため）。
    public static var current: APNsEnvironment {
        let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        let data = profileURL.flatMap { try? Data(contentsOf: $0) }
        if let resolved = resolve(embeddedProvisioningProfileData: data) {
            return resolved
        }
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        return .production
        #endif
    }

    /// 埋め込みプロビジョニングプロファイルの生バイト列から `aps-environment` を読み取り判定する純粋関数。
    /// プロファイルが無い・解析できない場合は nil を返す（呼び出し側でフォールバックする）。
    static func resolve(embeddedProvisioningProfileData data: Data?) -> APNsEnvironment? {
        guard let data, let value = apsEnvironmentValue(inProvisioningProfileData: data) else {
            return nil
        }
        return resolve(apsEnvironmentValue: value)
    }

    /// entitlements の `aps-environment` 文字列（"development" | "production"）から判定する純粋関数。
    static func resolve(apsEnvironmentValue value: String) -> APNsEnvironment {
        value == "development" ? .sandbox : .production
    }

    /// `embedded.mobileprovision` は CMS(PKCS#7) 署名で包まれた plist。
    /// バイト列中の `<?xml ... </plist>` 部分だけを抜き出してパースする（前後のバイナリ部分は無視する）。
    static func apsEnvironmentValue(inProvisioningProfileData data: Data) -> String? {
        guard let xmlStart = data.range(of: Data("<?xml".utf8)),
              let plistEnd = data.range(of: Data("</plist>".utf8), in: xmlStart.lowerBound..<data.endIndex)
        else {
            return nil
        }
        let plistData = data[xmlStart.lowerBound..<plistEnd.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else {
            return nil
        }
        return entitlements["aps-environment"] as? String
    }
}
