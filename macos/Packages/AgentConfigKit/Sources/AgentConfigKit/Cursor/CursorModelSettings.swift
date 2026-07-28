import Foundation

/// `cursor-agent models` が出す1行（`composer-2.5 - Composer 2.5`）。
public struct CursorModelOption: Sendable, Equatable, Identifiable {
    public let modelID: String
    public let displayName: String

    public var id: String { modelID }

    public init(modelID: String, displayName: String) {
        self.modelID = modelID
        self.displayName = displayName
    }
}

/// 既定モデルの読み書き。
///
/// cli-config.json は同じモデルを `model` と `selectedModel` の2か所に持っている。
/// 片方だけ書くと CLI の表示と実際に使うモデルがずれるため、**両方を揃えて書く**。
/// `aliases` や `modelParameters` など Phlox が意味を知らないキーは触らない。
public enum CursorModelSettings {
    public static func currentModelID(in root: JSONValue) -> String? {
        root.value(at: ["model", "modelId"])?.stringValue
    }

    public static func currentDisplayName(in root: JSONValue) -> String? {
        root.value(at: ["model", "displayName"])?.stringValue
    }

    public static func apply(_ option: CursorModelOption, to root: JSONValue) -> JSONValue {
        var next = root
        next = next.setting(["model", "modelId"], to: .string(option.modelID))
        next = next.setting(["model", "displayModelId"], to: .string(option.modelID))
        next = next.setting(["model", "displayName"], to: .string(option.displayName))
        next = next.setting(["model", "displayNameShort"], to: .string(option.displayName))
        next = next.setting(["selectedModel", "modelId"], to: .string(option.modelID))
        next = next.setting(["hasChangedDefaultModel"], to: .bool(true))
        return next
    }

    /// `cursor-agent models` の出力を選択肢へ写す。
    /// 見出し行や空行は落とし、`<id> - <表示名>` の形の行だけ拾う。
    public static func parseModels(from output: String) -> [CursorModelOption] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.range(of: " - ") else { return nil }
            let modelID = String(trimmed[trimmed.startIndex..<separator.lowerBound])
            let displayName = String(trimmed[separator.upperBound...])
            guard !modelID.isEmpty, !displayName.isEmpty, !modelID.contains(" ") else { return nil }
            return CursorModelOption(modelID: modelID, displayName: displayName)
        }
    }
}
