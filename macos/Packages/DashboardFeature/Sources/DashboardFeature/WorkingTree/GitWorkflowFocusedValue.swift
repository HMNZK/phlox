import SwiftUI

private struct GitWorkflowFocusedKey: FocusedValueKey {
    typealias Value = EditorPanelViewModel
}

extension FocusedValues {
    public var gitWorkflowModel: EditorPanelViewModel? {
        get { self[GitWorkflowFocusedKey.self] }
        set { self[GitWorkflowFocusedKey.self] = newValue }
    }
}
