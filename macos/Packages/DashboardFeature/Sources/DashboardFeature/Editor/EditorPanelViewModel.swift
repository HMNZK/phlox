import Foundation
import Observation

/// エディタパネル API の公開面を凍結するためのスタブ。
@MainActor
@Observable
public final class EditorPanelViewModel {
    public enum ListState: Equatable, Sendable {
        case noProject
        case notARepository
        case ready
    }

    public enum Detail: Equatable, Sendable {
        case none
        case diff(String)
        case content(String)
        case binary
    }

    public enum SaveResult: Equatable, Sendable {
        case saved
        case conflictDetected
    }

    public private(set) var listState: ListState = .noProject
    public private(set) var changes: [WorkingTreeChange] = []
    public private(set) var selectedPath: String?
    public private(set) var detail: Detail = .none
    public var draft = ""
    public private(set) var isDirty = false

    public init(service: WorkingTreeService?) {}

    public func refresh() async {}

    public func select(_ path: String) async {}

    public func save() async throws -> SaveResult {
        .conflictDetected
    }

    public func overwrite() async throws {}
}
