import SwiftUI
import DesignSystemIOS

public struct DotGothic16LicenseView: View {
    private let licenseText: String

    public init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "OFL", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            licenseText = text
        } else {
            licenseText = "DotGothic16 のライセンスを読み込めませんでした。"
        }
    }

    public var body: some View {
        ScrollView {
            Text(licenseText)
                .font(DSFont.body)
                .foregroundStyle(IOSColor.text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(DSSpacing.l)
        }
        .background(IOSColor.bg.base)
        .navigationTitle("DotGothic16 のライセンス")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
