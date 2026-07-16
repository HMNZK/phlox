import Foundation

public struct ComposerBranchPickerModel: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case presented
    }

    public private(set) var phase: Phase
    public private(set) var branches: [String]
    public private(set) var errorMessage: String?

    public init() {
        phase = .idle
        branches = []
        errorMessage = nil
    }

    public var isPresented: Bool {
        phase == .presented
    }

    public var allowsExternalRefresh: Bool {
        phase == .idle
    }

    public mutating func beginOpen() {
        guard phase == .idle else { return }
        phase = .loading
        branches = []
        errorMessage = nil
    }

    public mutating func finishLoading(_ result: Result<[String], Error>) {
        guard phase == .loading else { return }

        switch result {
        case let .success(branches):
            self.branches = branches
            phase = .presented
        case let .failure(error):
            branches = []
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    public mutating func select(branch: String) {
        guard phase == .presented else { return }
        phase = .idle
    }

    public mutating func dismiss() {
        phase = .idle
    }
}
