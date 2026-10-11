import Foundation

public enum ChatLaunchError: Error, Equatable, LocalizedError, Sendable {
    case processFailed(String)
    case settingsNotApplied(String)

    public var errorDescription: String? {
        switch self {
        case .processFailed(let message), .settingsNotApplied(let message): message
        }
    }
}

public enum SendRejected: Error, Equatable, LocalizedError, Sendable {
    case totalSizeExceeded
    case imagesUnsupported
    case skillReselectionRequired

    public var errorDescription: String? {
        switch self {
        case .totalSizeExceeded: "画像は合計80MBまでです"
        case .imagesUnsupported: "画像添付は Claude と画像対応モデルの Codex に対応しています"
        case .skillReselectionRequired: "Codex skill の候補が更新されたため、送信前に skill を再選択してください。"
        }
    }
}
