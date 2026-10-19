import DesignSystemIOS
import SwiftUI

/// 新規／既存セッションで共用するモデル選択面。説明も一覧と一緒にスクロールする。
struct ModelSelectionSheet<Content: View>: View {
    let title: String
    @Binding var searchText: String
    let explanation: String
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Text("閉じる")
                        .font(DSFont.body.weight(.semibold))
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(IOSColor.bg.fill, in: Capsule())
                }
                .buttonStyle(DSPressFeedbackStyle())
                Text(title)
                    .font(DSFont.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(IOSColor.text.primary)
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(IOSColor.text.secondary)
                TextField("絞り込み", text: $searchText)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                    .accessibilityLabel("モデルを絞り込む")
            }
            .font(DSFont.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(IOSColor.bg.fill, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                    Text(explanation)
                        .font(DSFont.iosCaption2)
                        .foregroundStyle(IOSColor.text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 20)
        .background(IOSColor.bg.sheet)
    }
}
