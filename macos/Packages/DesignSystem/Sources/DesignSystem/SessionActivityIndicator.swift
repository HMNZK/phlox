import SwiftUI

extension SessionDisplayState {
    public var showsActivityIndicator: Bool { self == .running || self == .doneUnread }
}

/// 実行中はスピナー、まだ確認していない完了は緑のチェック。
public struct SessionActivityIndicator: View {
    public let state: SessionDisplayState
    @Environment(\.locale) private var locale

    public init(state: SessionDisplayState) {
        self.state = state
    }

    public var body: some View {
        if state == .running {
            SessionRunningSpinner()
        } else if state == .doneUnread {
            SessionSuccessIndicator()
                .frame(width: SessionRunningSpinner.diameter, height: SessionRunningSpinner.diameter)
                .fixedSize()
                .help(Text(verbatim: state.localizedLabel(locale: locale)))
                .accessibilityHidden(true)
        }
    }
}
