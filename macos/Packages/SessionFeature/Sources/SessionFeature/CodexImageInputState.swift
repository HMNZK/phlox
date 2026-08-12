import CodexAppServerKit

/// Codex の画像入力可否を model/list の modality だけから判定する。
/// 対応確認済みの model だけを許可する。
enum CodexImageInputState {
    private static let knownModalities: Set<String> = ["text", "image"]

    static func acceptsImageAttachments(
        selectedModel: String?,
        availableModels: [AppServerModel]
    ) -> Bool {
        guard !availableModels.isEmpty else { return false }

        let model: AppServerModel?
        if let selectedModel {
            model = availableModels.first { candidate in
                candidate.id == selectedModel || candidate.model == selectedModel
            }
        } else {
            model = availableModels.first(where: \.isDefault)
        }

        guard let modalities = model?.inputModalities else { return false }
        return modalities.contains("image")
            && modalities.allSatisfy { knownModalities.contains($0) }
    }
}
