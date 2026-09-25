import SwiftUI
import DesignSystem

/// プロセスが終わったセッションの入力欄の代わり（04 B3・PhloxChat の showEnded）。
/// 「セッションは終了しました（exit N）。会話は保存されています。」と「この会話から再開」。
struct ChatProcessEndedStrip: View {
    let exit: ChatProcessExit
    let onResume: (@MainActor () -> Void)?
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    var body: some View {
        let _ = themeID
        HStack(spacing: 10) {
            Text(Self.message(exitCode: exit.exitCode))
                .font(.system(size: 12.5))
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onResume {
                Button("この会話から再開") { onResume() }
                    .buttonStyle(DSButtonStyle(.secondary, height: 24, fontSize: 12, padding: 10))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(DSColor.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .padding(.horizontal, DSSpacing.m)
        .padding(.top, DSSpacing.s)
        .padding(.bottom, DSSpacing.m)
    }

    static func message(exitCode: Int32?) -> LocalizedStringKey {
        if let exitCode {
            return "セッションは終了しました（exit \(Int(exitCode))）。会話は保存されています。"
        }
        return "セッションは終了しました。会話は保存されています。"
    }
}
