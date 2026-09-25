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
    /// 切り替えに失敗した理由。一覧の下に出す（PhloxReply O7「main に切り替えられません: …」）。
    public private(set) var checkoutErrorMessage: String?

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
        checkoutErrorMessage = nil
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

    /// 選んでも閉じない。切り替えが済んだら閉じ、失敗したら一覧の中に理由を出す（B3）。
    public mutating func select(branch: String) {
        guard phase == .presented else { return }
        checkoutErrorMessage = nil
    }

    public mutating func finishCheckout(_ result: Result<Void, Error>, branch: String) {
        guard phase == .presented else { return }
        switch result {
        case .success:
            phase = .idle
        case let .failure(error):
            checkoutErrorMessage = error.localizedDescription
        }
    }

    public mutating func dismiss() {
        phase = .idle
        checkoutErrorMessage = nil
    }
}
