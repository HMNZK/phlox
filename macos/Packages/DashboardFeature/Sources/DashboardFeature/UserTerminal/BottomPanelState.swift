import AppKit
import AgentDomain
import DesignSystem
import Observation
import SwiftUI

private struct BottomPanelFocusedValueKey: FocusedValueKey {
    typealias Value = BottomPanelState
}

extension FocusedValues {
    public var bottomPanelState: BottomPanelState? {
        get { self[BottomPanelFocusedValueKey.self] }
        set { self[BottomPanelFocusedValueKey.self] = newValue }
    }
}

enum BottomPanelLayout {
    static func maximumHeight(availableHeight: CGFloat) -> CGFloat {
        max(0, min(availableHeight * DSLayout.bottomPanelMaximumFraction,
                   availableHeight - DSLayout.bottomPanelContentMinimumHeight))
    }

    static func clamped(_ proposed: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let maximum = maximumHeight(availableHeight: availableHeight)
        return min(maximum, max(min(DSLayout.bottomPanelMinimumHeight, maximum), proposed))
    }
}

/// ウィンドウ単位。親の会話・グリッドはこの状態を購読しない。
@MainActor @Observable
public final class BottomPanelState {
    static let heightKey = "phlox.bottomPanel.height"
    public private(set) var isVisible = false
    public var isTerminalFocused = false
    public private(set) var focusRequest = 0
    public private(set) var preferredHeight: CGFloat
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var returnResponder: NSResponder?
    @ObservationIgnored private weak var returnWindow: NSWindow?

    public init(defaults: UserDefaults = .phloxDefaults()) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.heightKey)
        preferredHeight = stored.isFinite && stored > 0 ? stored : DSLayout.bottomPanelDefaultHeight
    }

    public func toggle(projectID: ProjectID?, window: NSWindow? = NSApp.keyWindow) {
        guard projectID != nil else { return }
        if isVisible { close() } else { open(window: window) }
    }

    public func open(window: NSWindow? = NSApp.keyWindow) {
        if !isVisible {
            returnWindow = window
            returnResponder = window?.firstResponder
        }
        isVisible = true
        focusRequest += 1
    }

    public func close() {
        isVisible = false
        isTerminalFocused = false
        if let window = returnWindow, let view = returnResponder as? NSView, view.window === window {
            window.makeFirstResponder(view)
        }
        returnResponder = nil
        returnWindow = nil
    }

    func saveHeight(_ value: CGFloat, availableHeight: CGFloat) {
        preferredHeight = BottomPanelLayout.clamped(value, availableHeight: availableHeight)
        defaults.set(Double(preferredHeight), forKey: Self.heightKey)
    }

    public static func targetProjectID(mode: ViewMode, selectedProjectID: ProjectID?, selectedTileProjectID: ProjectID?) -> ProjectID? {
        mode == .grid ? selectedTileProjectID ?? selectedProjectID : selectedProjectID
    }
}
