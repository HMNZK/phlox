import CoreGraphics
import SessionFeature

public struct CustomGridLayout: Codable, Equatable, Sendable {
    public var tree: PaneTree
    public var presetState: PaneLayoutStore.PresetState
    public var canvasMinimum: CGSize

    public init(tree: PaneTree, presetState: PaneLayoutStore.PresetState = .init(), canvasMinimum: CGSize = .zero) {
        self.tree = tree
        self.presetState = presetState
        self.canvasMinimum = canvasMinimum
    }
}

public enum GridLayoutState: Codable, Equatable, Sendable {
    case automatic(previousCustom: CustomGridLayout?)
    case custom(CustomGridLayout)

    public var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }

    public var customLayout: CustomGridLayout? {
        switch self {
        case .automatic(let previous): return previous
        case .custom(let layout): return layout
        }
    }
}
