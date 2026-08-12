import CodexAppServerKit

/// Codex の画像入力可否を model/list の modality だけから判定する。
/// 未取得時は起動直後の既存送信経路を維持し、取得済みなら `image` のみを許可する。
enum CodexImageInputState {
    private static let knownModalities: Set<String> = ["text", "image"]

    static func acceptsImageAttachments(
        selectedModel: String?,
        availableModels: [AppServerModel],
        allowWhenUnavailable: Bool = true
    ) -> Bool {
        guard !availableModels.isEmpty else { return allowWhenUnavailable }

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
