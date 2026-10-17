import Foundation
import AgentDomain
import ControlServer
import SessionFeature
import DesignSystem

public struct NewChatSettingsOptions: Encodable, Sendable {
    public let availableEfforts: [String: [ControlSettingOption]]
    public let availablePermissions: [ControlSettingOption]
    public let planModeAvailable: Bool
}

/// 新規チャット画面と Control API が使う選択肢。
public func newChatSettingsOptions(for kind: AgentKind, languageCode: String, bundle: Bundle = .main) -> NewChatSettingsOptions {
    let efforts = Dictionary(uniqueKeysWithValues: AgentModelCatalog.models(for: kind).map { model in
        (model.id, newChatEffortOptions(for: kind, modelID: model.id, languageCode: languageCode, bundle: bundle))
    })
    let permissions = composerModeOptions(for: .builtin(kind), codexProfileIDs: [":danger-full-access", ":workspace", ":read-only"], languageCode: languageCode)
        .filter { !$0.isPlan }
        .map { option in
            ControlSettingOption(value: option.value, displayName: kind == .cursor && option.value == nil
                ? AppLocalizedString.string("既定", locale: Locale(identifier: languageCode), bundle: bundle)
                : option.title)
        }
    return NewChatSettingsOptions(availableEfforts: efforts, availablePermissions: permissions, planModeAvailable: true)
}

public func newChatEffortOptions(for kind: AgentKind, modelID: String?, languageCode: String, bundle: Bundle = .main) -> [ControlSettingOption] {
    let values: [String]
    switch kind {
    case .claudeCode:
        values = modelID?.split(separator: "[", maxSplits: 1).first == "haiku"
            ? [] : ["low", "medium", "high", "xhigh", "max"]
    case .codex, .cursor:
        values = AgentModelCatalog.models(for: kind).first { $0.id == modelID }?.reasoningEfforts ?? []
    }
    return values.map {
        ControlSettingOption(value: $0, displayName: composerEffortTitle($0, languageCode: languageCode, bundle: bundle))
    }
}
