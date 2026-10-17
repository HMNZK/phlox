import Foundation
import AgentDomain
import ControlServer
import SessionFeature
import DesignSystem

/// 新規チャット画面と Control API が使う選択肢。
public func newChatSettingsOptions(
    for kind: AgentKind,
    languageCode: String,
    bundle: Bundle = .main,
    fullAccessEnabled: Bool? = nil
) -> ControlAgentSettings {
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
    let fullAccess = fullAccessEnabled ?? BypassSettings.isEnabled(for: kind)
    let defaultsByModel = Dictionary(AgentModelCatalog.models(for: kind).compactMap { model in
        newChatDefaultSettings(for: kind, modelID: model.id, fullAccess: fullAccess)
            .selectedEffort
            .map { (model.id, $0) }
    }, uniquingKeysWith: { first, _ in first })
    let defaults = newChatDefaultSettings(
        for: kind,
        modelID: AgentModelCatalog.defaultModel(for: kind),
        fullAccess: fullAccess
    )
    return ControlAgentSettings(
        availableEfforts: efforts,
        availablePermissions: permissions,
        planModeAvailable: true,
        defaultEfforts: defaultsByModel.isEmpty ? nil : defaultsByModel,
        defaultPermission: defaults.selectedPermissionProfile
    )
}

/// Mac の新規チャットが保存値なしで使う、モデル・推論の深さ・権限の既定。
public func newChatDefaultSettings(
    for kind: AgentKind,
    modelID: String?,
    fullAccess: Bool
) -> CodexAppServerSessionSettings {
    let modelOption = AgentModelCatalog.models(for: kind).first { $0.id == modelID }
    let fallbackEffort = kind == .claudeCode && modelID?.split(separator: "[", maxSplits: 1).first != "haiku"
        ? "high" : nil
    let candidateEffort = modelOption?.defaultReasoningEffort ?? fallbackEffort
    let availableEfforts = newChatEffortOptions(for: kind, modelID: modelID, languageCode: "en")
    let effort = availableEfforts.contains(where: { $0.value == candidateEffort }) ? candidateEffort : nil
    return CodexAppServerSessionSettings(
        selectedModel: modelID ?? AgentModelCatalog.defaultModel(for: kind),
        selectedEffort: effort,
        selectedPermissionProfile: kind == .claudeCode
            ? (fullAccess ? "bypassPermissions" : "auto")
            : nil,
        isPlanMode: false
    )
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
