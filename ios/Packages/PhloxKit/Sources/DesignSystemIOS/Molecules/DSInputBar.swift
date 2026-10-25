import AgentDomain
import DesignSystem
import Foundation
import ImageAttachmentKit
import PhloxCore
import SwiftUI

#if os(iOS)
    import PhotosUI
    import UIKit
#endif

/// 添付ストリップの1件（確定時に生成済みの小さいプレビューのみ。フル解像度は ViewModel 側で保持）。
public struct DSAttachmentStripItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 本文の `[Image #N]` と対応する表示番号（1始まり）。
    public let number: Int
    public let previewData: Data

    public init(id: UUID, number: Int = 1, previewData: Data) {
        self.id = id
        self.number = number
        self.previewData = previewData
    }
}

/// Mac から届いた設定項目。表示名はそのまま使い、値は API に送る。
public struct DSInputBarSettingOption: Identifiable, Equatable, Sendable {
    public let value: String?
    public let displayName: String

    public var id: String { value ?? "__default__" }

    public init(value: String?, displayName: String) {
        self.value = value
        self.displayName = displayName
    }
}

/// 新規チャットのプロジェクト選択メニューに渡す項目。
public struct DSInputBarProjectOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isLastUsed: Bool

    public init(id: String, name: String, isLastUsed: Bool = false) {
        self.id = id
        self.name = name
        self.isLastUsed = isLastUsed
    }
}

/// 入力欄の設定チップに渡す値と操作。新規チャットは段階 5 で同じ設定を渡す。
public struct DSInputBarSettings {
    public let agentName: String
    public let effortOptions: [DSInputBarSettingOption]
    public let selectedEffort: String?
    public let permissionOptions: [DSInputBarSettingOption]
    public let selectedPermission: String?
    public let planMode: Bool
    public let planModeAvailable: Bool
    public let isUpdatingEffort: Bool
    public let isUpdatingPermission: Bool
    public let isUpdatingPlanMode: Bool
    public let onSelectEffort: (String?) -> Void
    public let onSelectPermission: (String?) -> Void
    public let onSelectPlanMode: (Bool) -> Void

    public init(
        agentName: String,
        effortOptions: [DSInputBarSettingOption] = [],
        selectedEffort: String? = nil,
        permissionOptions: [DSInputBarSettingOption] = [],
        selectedPermission: String? = nil,
        planMode: Bool = false,
        planModeAvailable: Bool = false,
        isUpdatingEffort: Bool = false,
        isUpdatingPermission: Bool = false,
        isUpdatingPlanMode: Bool = false,
        onSelectEffort: @escaping (String?) -> Void = { _ in },
        onSelectPermission: @escaping (String?) -> Void = { _ in },
        onSelectPlanMode: @escaping (Bool) -> Void = { _ in }
    ) {
        self.agentName = agentName
        self.effortOptions = effortOptions
        self.selectedEffort = selectedEffort
        self.permissionOptions = permissionOptions
        self.selectedPermission = selectedPermission
        self.planMode = planMode
        self.planModeAvailable = planModeAvailable
        self.isUpdatingEffort = isUpdatingEffort
        self.isUpdatingPermission = isUpdatingPermission
        self.isUpdatingPlanMode = isUpdatingPlanMode
        self.onSelectEffort = onSelectEffort
        self.onSelectPermission = onSelectPermission
        self.onSelectPlanMode = onSelectPlanMode
    }
}

public enum DSInputBarMode: Sendable, Equatable {
    case session
    case newChat
}

struct DSInputBarActionState: Equatable {
    let showsStop: Bool
    let showsSend: Bool
    let sendIsEnabled: Bool
}

/// 幅だけで圧縮順を決める。文字幅は ClaudeDesign の Reply/Draft `cmpVals` と同じ近似式。
struct DSInputBarLayout: Equatable {
    let mergesSettings: Bool
    let showsProjectIconOnly: Bool
    let wrapsSecondRow: Bool
    let keepsStrongPermissionVisible: Bool

    static func resolve(
        width: CGFloat,
        mode: DSInputBarMode,
        isAccessibilitySize: Bool,
        hasModel: Bool,
        modelName: String,
        effortName: String?,
        permissionName: String?,
        isStrongPermission: Bool,
        hasText: Bool,
        isRunning: Bool,
        hasProject: Bool,
        projectName: String?
    ) -> Self {
        let metrics = Metrics(isAccessibilitySize: isAccessibilitySize)
        let hasEffort = effortName != nil
        let hasPermission = permissionName != nil
        let isDraft = mode == .newChat
        let innerWidth = max(0, width - 14)
        let modelWidth = chipWidth(modelName, hasIcon: false, hasLogo: true, hasChevron: true, metrics: metrics)
        let effortWidth = effortName.map {
            chipWidth($0, hasIcon: true, hasLogo: false, hasChevron: false, metrics: metrics)
        } ?? 0
        let permissionWidth = permissionName.map {
            chipWidth($0, hasIcon: true, hasLogo: false, hasChevron: false, metrics: metrics)
        } ?? 0
        let sendWidth = isRunning && hasText
            ? metrics.buttonWidth * 2 + metrics.controlGap
            : metrics.buttonWidth

        func widthAt(_ level: Int) -> CGFloat {
            var result = metrics.buttonWidth
            if hasModel { result += metrics.controlGap + modelWidth }
            if level == 0 {
                if hasEffort { result += metrics.controlGap + effortWidth }
                if hasPermission { result += metrics.controlGap + permissionWidth }
            } else if isStrongPermission {
                if hasEffort { result += metrics.controlGap + metrics.buttonWidth }
                if hasPermission { result += metrics.controlGap + permissionWidth }
            } else if hasEffort || hasPermission {
                result += metrics.controlGap + metrics.buttonWidth
            }
            if isDraft && hasProject {
                let projectLabel: String
                if level >= 2 {
                    projectLabel = ""
                } else {
                    projectLabel = projectName.flatMap { $0.isEmpty ? nil : $0 } ?? "プロジェクト"
                }
                result += metrics.controlGap + chipWidth(
                    projectLabel,
                    hasIcon: true,
                    hasLogo: false,
                    hasChevron: true,
                    metrics: metrics
                )
            }
            result += metrics.controlGap + sendWidth + 2
            return result
        }

        var level = isAccessibilitySize ? 1 : 0
        while level < 2 && widthAt(level) > innerWidth { level += 1 }
        return Self(
            mergesSettings: level >= 1,
            showsProjectIconOnly: isDraft && hasProject && level >= 2,
            wrapsSecondRow: widthAt(level) > innerWidth,
            keepsStrongPermissionVisible: isStrongPermission && hasPermission
        )
    }

    private struct Metrics {
        let iconSize: CGFloat
        let logoSize: CGFloat
        let chipHeight: CGFloat
        let horizontalPadding: CGFloat
        let controlGap: CGFloat
        let chipFontSize: CGFloat
        let buttonWidth: CGFloat

        init(isAccessibilitySize: Bool) {
            if isAccessibilitySize {
                iconSize = 26
                logoSize = 26
                chipHeight = 58
                horizontalPadding = 12
                controlGap = 6
                chipFontSize = 26
                buttonWidth = 58
            } else {
                iconSize = 14
                logoSize = 15
                chipHeight = 34
                horizontalPadding = 7
                controlGap = 3
                chipFontSize = 13
                buttonWidth = 34
            }
        }
    }

    private static func chipWidth(
        _ label: String,
        hasIcon: Bool,
        hasLogo: Bool,
        hasChevron: Bool,
        metrics: Metrics
    ) -> CGFloat {
        (hasLogo ? metrics.logoSize + 4 : 0)
            + (hasIcon ? metrics.iconSize + 4 : 0)
            + textWidth(label, fontSize: metrics.chipFontSize)
            + (hasChevron ? metrics.iconSize * 0.8 + 3 : 0)
            + metrics.horizontalPadding * 2
    }

    private static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        text.unicodeScalars.reduce(CGFloat.zero) { width, scalar in
            let value = scalar.value
            if value > 0xFF { return width + fontSize }
            if (65...90).contains(value) || (48...57).contains(value) { return width + fontSize * 0.64 }
            if (97...122).contains(value) { return width + fontSize * 0.53 }
            return width + fontSize * 0.33
        }
    }
}

/// 2 段の入力欄。iOS 26 は Liquid Glass、iOS 18 は同じ角丸の素材面と細い線。
public struct DSInputBar: View {
    static let sendButtonIconName = "arrow.up"
    static let stopButtonIconName = "stop.fill"
    static let usesFocusState = true
    static let providesCursorAwareInput = true
    static let maximumTextLineCount = 5
    static let attachmentThumbnailSize: CGFloat = 56
    static let chipVisualHeight: CGFloat = 34
    static let chipTouchTargetSize: CGFloat = 44
    public static let sendAccessibilityLabel = "送信"
    public static let stopAccessibilityLabel = "停止"

    @Binding var text: String
    @Binding var cursorUTF16: Int
    let placeholder: String
    let isLoading: Bool
    let attachmentStrip: [DSAttachmentStripItem]
    let attachmentError: String?
    let settingsError: String?
    let contextLabel: String?
    let maxAttachments: Int
    let onAddAttachments: (([Result<SendAttachment, Error>]) -> Void)?
    let onRemoveAttachment: ((Int) -> Void)?
    let onAttachmentLimitReached: (() -> Void)?
    let isRunning: Bool
    let onStop: () -> Void
    let mode: DSInputBarMode
    let model: (kind: AgentKind, displayName: String)?
    let onSelectModel: (() -> Void)?
    let settings: DSInputBarSettings?
    let projectName: String?
    let onSelectProject: (() -> Void)?
    let projectOptions: [DSInputBarProjectOption]
    let selectedProjectID: String?
    let onSelectProjectID: ((String) -> Void)?
    let focusOnAppear: Bool
    let focusRequest: Int
    let skills: [AgentSkill]
    let skillsLoading: Bool
    let skillsError: String?
    let onSelectSkill: ((AgentSkill) -> Void)?
    let onSubmit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @State private var isFocused = false
    #else
    @FocusState private var isFocused: Bool
    #endif
    @State private var measuredWidth: CGFloat = 0
    @State private var placeholderNaturalHeight: CGFloat = 0
    @State private var placeholderSingleLineHeight: CGFloat = 0
    @State private var pendingDangerousPermission: DSInputBarSettingOption?
    #if os(iOS)
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    #endif

    public init(
        text: Binding<String>,
        cursorUTF16: Binding<Int> = .constant(0),
        placeholder: String = "やりたいことを入力",
        isLoading: Bool = false,
        attachmentStrip: [DSAttachmentStripItem] = [],
        attachmentError: String? = nil,
        settingsError: String? = nil,
        contextLabel: String? = nil,
        maxAttachments: Int = 4,
        onAddAttachments: (([Result<SendAttachment, Error>]) -> Void)? = nil,
        onRemoveAttachment: ((Int) -> Void)? = nil,
        onAttachmentLimitReached: (() -> Void)? = nil,
        isRunning: Bool = false,
        onStop: @escaping () -> Void = {},
        mode: DSInputBarMode = .session,
        model: (kind: AgentKind, displayName: String)? = nil,
        onSelectModel: (() -> Void)? = nil,
        settings: DSInputBarSettings? = nil,
        projectName: String? = nil,
        onSelectProject: (() -> Void)? = nil,
        projectOptions: [DSInputBarProjectOption] = [],
        selectedProjectID: String? = nil,
        onSelectProjectID: ((String) -> Void)? = nil,
        focusOnAppear: Bool = false,
        focusRequest: Int = 0,
        skills: [AgentSkill] = [],
        skillsLoading: Bool = false,
        skillsError: String? = nil,
        onSelectSkill: ((AgentSkill) -> Void)? = nil,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self._cursorUTF16 = cursorUTF16
        self.placeholder = placeholder
        self.isLoading = isLoading
        self.attachmentStrip = attachmentStrip
        self.attachmentError = attachmentError
        self.settingsError = settingsError
        self.contextLabel = contextLabel
        self.maxAttachments = maxAttachments
        self.onAddAttachments = onAddAttachments
        self.onRemoveAttachment = onRemoveAttachment
        self.onAttachmentLimitReached = onAttachmentLimitReached
        self.isRunning = isRunning
        self.onStop = onStop
        self.mode = mode
        self.model = model
        self.onSelectModel = onSelectModel
        self.settings = settings
        self.projectName = projectName
        self.onSelectProject = onSelectProject
        self.projectOptions = projectOptions
        self.selectedProjectID = selectedProjectID
        self.onSelectProjectID = onSelectProjectID
        self.focusOnAppear = focusOnAppear
        self.focusRequest = focusRequest
        self.skills = skills
        self.skillsLoading = skillsLoading
        self.skillsError = skillsError
        self.onSelectSkill = onSelectSkill
        self.onSubmit = onSubmit
    }

    static func canSubmit(text: String, isLoading: Bool) -> Bool {
        DSSubmitBarLogic.canSubmit(text: text, isLoading: isLoading)
    }

    static func actionState(text: String, isLoading: Bool, isRunning: Bool) -> DSInputBarActionState {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return DSInputBarActionState(
            showsStop: isRunning,
            showsSend: !isRunning || hasText || isLoading,
            sendIsEnabled: canSubmit(text: text, isLoading: isLoading)
        )
    }

    private var actionState: DSInputBarActionState {
        Self.actionState(text: text, isLoading: isLoading, isRunning: isRunning)
    }

    private var layout: DSInputBarLayout {
        DSInputBarLayout.resolve(
            width: max(0, measuredWidth - 24),
            mode: mode,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            hasModel: model != nil,
            modelName: model?.displayName ?? "",
            effortName: showsEffortChip ? currentEffortName : nil,
            permissionName: showsPermissionChip ? currentPermissionName : nil,
            isStrongPermission: isStrongPermissionSelected,
            hasText: !text.isEmpty,
            isRunning: isRunning,
            hasProject: mode == .newChat && (projectName != nil || onSelectProject != nil || onSelectProjectID != nil),
            projectName: projectName
        )
    }

    private var hasEffortOptions: Bool { !(settings?.effortOptions.isEmpty ?? true) }
    private var hasPermissionOptions: Bool { !(settings?.permissionOptions.isEmpty ?? true) }
    private var showsEffortChip: Bool { hasEffortOptions }
    private var showsPermissionChip: Bool { hasPermissionOptions }
    private var currentEffortName: String {
        guard let settings else { return "" }
        if let option = settings.effortOptions.first(where: { $0.value == settings.selectedEffort }) {
            return option.displayName
        }
        return settings.selectedEffort == nil ? "既定" : (settings.effortOptions.first?.displayName ?? "")
    }
    private var currentPermissionName: String {
        guard let settings else { return "" }
        if settings.planMode { return "Plan" }
        if let option = settings.permissionOptions.first(where: { $0.value == settings.selectedPermission }) {
            return option.displayName
        }
        return "既定"
    }
    private var isStrongPermissionSelected: Bool {
        guard settings?.planMode == false,
              let value = settings?.selectedPermission else { return false }
        return Self.isStrongPermissionValue(value)
    }

    static func isStrongPermissionValue(_ value: String) -> Bool {
        value == "bypassPermissions" || value == ":danger-full-access"
    }

    public var body: some View {
        observeWidth(
            VStack(alignment: .leading, spacing: DSSpacing.chip) {
                skillSuggestions
                if let contextLabel, !contextLabel.isEmpty {
                    Label(contextLabel, systemImage: "arrow.triangle.branch")
                        .font(DSFont.inputBar(.caption, for: dynamicTypeSize))
                        .foregroundStyle(DSColor.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, DSSpacing.m)
                }
                if let settingsError { errorLine(settingsError) }
                if let attachmentError { errorLine(attachmentError) }

                VStack(alignment: .leading, spacing: DSSpacing.chip) {
                    if !attachmentStrip.isEmpty { attachmentStripView }
                    inputTextField
                        .padding(.horizontal, 10)
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 53 : 24, alignment: .topLeading)

                    controlsSection
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(.inputField)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(IOSColor.text.primary.opacity(isFocused ? 0.4 : 0), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        )
        #if os(iOS)
            .onChange(of: selectedPhotoItems) { _, items in
                guard onAddAttachments != nil else { return }
                Task { await importSelectedPhotos(items) }
            }
            .onAppear {
                guard focusOnAppear else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    isFocused = true
                }
            }
            .onChange(of: focusRequest) { _, _ in
                guard focusOnAppear else { return }
                isFocused = true
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedPhotoItems,
                maxSelectionCount: max(1, maxAttachments - attachmentStrip.count),
                selectionBehavior: .ordered,
                matching: .images
            )
        #endif
        .alert("確認なしで全部を許可しますか？", isPresented: dangerousPermissionAlertIsPresented) {
            Button("キャンセル", role: .cancel) {
                pendingDangerousPermission = nil
            }
            if let pendingDangerousPermission {
                Button("\(pendingDangerousPermission.displayName) にする", role: .destructive) {
                    settings?.onSelectPermission(pendingDangerousPermission.value)
                    self.pendingDangerousPermission = nil
                }
            }
        }
    }

    @ViewBuilder
    private var skillSuggestions: some View {
        if let query = SkillSuggestionQuery.detect(text: text, cursorUTF16: cursorUTF16) {
            if skillsLoading {
                ProgressView("スキルを取得中")
                    .font(DSFont.inputBar(.caption, for: dynamicTypeSize))
                    .padding(.horizontal, DSSpacing.m)
            } else if let skillsError {
                errorLine(skillsError)
            } else {
                let matches = skills.filter(query.matches)
                if !matches.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(matches) { skill in
                                Button {
                                    let result = query.inserting(skill, into: text, agent: model?.kind ?? .claudeCode)
                                    text = result.text
                                    cursorUTF16 = result.cursorUTF16
                                    onSelectSkill?(skill)
                                    isFocused = true
                                } label: {
                                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                        Text("/" + skill.name).font(DSFont.inputBar(.textField, for: dynamicTypeSize).weight(.semibold))
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(DSFont.inputBar(.caption, for: dynamicTypeSize))
                                                .foregroundStyle(DSColor.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, DSSpacing.m)
                                    .padding(.vertical, DSSpacing.xs)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("/" + skill.name)
                                .accessibilityHint(skill.description)
                                .accessibilityIdentifier("skill-suggestion-" + skill.name)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .fixedSize(horizontal: false, vertical: true)
                    .glassSurface(.inputField)
                    .padding(.horizontal, 12)
                    .accessibilityLabel("スキル候補")
                }
            }
        }
    }

    @ViewBuilder
    private func observeWidth<Content: View>(_ content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                guard width.isFinite, width > 0 else { return }
                Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(16))
                    } catch {
                        return
                    }
                    guard abs(measuredWidth - width) > 0.5 else { return }
                    measuredWidth = width
                }
            }
        } else {
            content
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: DSInputBarWidthKey.self, value: proxy.size.width)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .onPreferenceChange(DSInputBarWidthKey.self) { width in
                    guard width.isFinite, width > 0 else { return }
                    Task { @MainActor in
                        await Task.yield()
                        guard abs(measuredWidth - width) > 0.5 else { return }
                        measuredWidth = width
                    }
                }
        }
    }

    private var dangerousPermissionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDangerousPermission != nil },
            set: { if !$0 { pendingDangerousPermission = nil } }
        )
    }

    private func errorLine(_ message: String) -> some View {
        Text(message)
            .font(DSFont.inputBar(.error, for: dynamicTypeSize).weight(.semibold))
            .foregroundStyle(IOSColor.status.error)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var inputTextField: some View {
        let usesExpandedPlaceholder = dynamicTypeSize.isAccessibilitySize && text.isEmpty
        let minimumTextLineCount = usesExpandedPlaceholder ? expandedPlaceholderMinimumLineCount : 1
        ZStack(alignment: usesExpandedPlaceholder ? .topLeading : .leading) {
            if text.isEmpty {
                placeholderText
                    .font(DSFont.inputBar(.textField, for: dynamicTypeSize))
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        guard usesExpandedPlaceholder, height.isFinite, height >= 0 else { return }
                        placeholderNaturalHeight = height
                    }
                    .background {
                        Text(placeholder)
                            .font(DSFont.inputBar(.textField, for: dynamicTypeSize))
                            .lineLimit(1)
                            .fixedSize()
                            .hidden()
                            .accessibilityHidden(true)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                guard height.isFinite, height >= 0 else { return }
                                placeholderSingleLineHeight = height
                            }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        #if os(iOS)
            DSInputRichTextEditor(
                text: $text,
                cursorUTF16: $cursorUTF16,
                isFocused: $isFocused,
                dynamicTypeSize: dynamicTypeSize,
                accessibilityLabel: placeholder
            )
            .frame(minHeight: usesExpandedPlaceholder ? placeholderNaturalHeight : 0)
        #else
            TextField(text: $text, axis: .vertical) { EmptyView() }
            .font(DSFont.inputBar(.textField, for: dynamicTypeSize))
            .foregroundStyle(IOSColor.text.primary)
            .tint(IOSColor.accent)
            .lineLimit(minimumTextLineCount...max(Self.maximumTextLineCount, minimumTextLineCount))
            .focused($isFocused)
            .accessibilityLabel(Text(placeholder))
        #endif
        }
        .fixedSize(horizontal: false, vertical: usesExpandedPlaceholder)
    }

    private var expandedPlaceholderMinimumLineCount: Int {
        guard placeholderNaturalHeight > 0, placeholderSingleLineHeight > 0 else { return 1 }
        return max(1, Int(ceil(placeholderNaturalHeight / placeholderSingleLineHeight)))
    }

    private var placeholderText: some View {
        Text(placeholder)
            .foregroundStyle(IOSColor.text.tertiary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
    }

    private var attachmentStripView: some View {
        HStack(spacing: DSSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.s) {
                    ForEach(attachmentStrip) { attachmentThumbnail($0) }
                }
                .padding(.vertical, DSSpacing.xs)
            }
            Spacer(minLength: DSSpacing.xs)
            Text("画像 \(attachmentStrip.count)/\(maxAttachments)")
                .font(DSFont.inputBar(.caption, for: dynamicTypeSize))
                .foregroundStyle(IOSColor.text.secondary)
                .fixedSize()
        }
        .padding(.horizontal, DSSpacing.s)
    }

    @ViewBuilder
    private func attachmentThumbnail(_ item: DSAttachmentStripItem) -> some View {
        let index = attachmentStrip.firstIndex(where: { $0.id == item.id }) ?? 0
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                attachmentPreview(for: item.previewData)
                    .frame(width: Self.attachmentThumbnailSize, height: Self.attachmentThumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(IOSColor.bg.separator, lineWidth: 1)
                    )
                Text("#\(item.number)")
                    .font(DSFont.campMonoCaption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
                    .padding(4)
                    .accessibilityHidden(true)
            }
            if let onRemoveAttachment {
                Button { onRemoveAttachment(index) } label: {
                    Image(systemName: "xmark")
                        .font(DSFont.inputBar(.removeSymbol, for: dynamicTypeSize).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(IOSColor.text.primary, in: Circle())
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressFeedbackStyle())
                .offset(x: 8, y: -8)
                .accessibilityLabel("添付 \(item.number) を削除")
            }
        }
        .frame(width: 60, height: 64)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func attachmentPreview(for data: Data) -> some View {
        #if os(iOS)
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            attachmentPlaceholder
        }
        #else
        attachmentPlaceholder
        #endif
    }

    private var attachmentPlaceholder: some View {
        ZStack {
            DSColor.fillSubtle
            Image(systemName: "photo")
                .foregroundStyle(IOSColor.text.tertiary)
        }
    }

    private var controlsSection: some View {
        let layout = layout
        return Group {
            if layout.wrapsSecondRow {
                if dynamicTypeSize.isAccessibilitySize && !isStrongPermissionSelected {
                    ViewThatFits(in: .horizontal) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: controlSpacing) {
                                leadingControls(layout: layout)
                                if showsProjectSelector { projectSelector(iconOnly: true) }
                            }
                            actionButtons
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                leadingControls(layout: layout, movesSettingsMenuToWrappedRow: true)
                            }
                            .frame(height: 58)
                            HStack(spacing: controlSpacing) {
                                moreSettingsMenu
                                Spacer(minLength: 0)
                                if showsProjectSelector { projectSelector(iconOnly: true) }
                                actionButtons
                            }
                        }
                    }
                } else {
                    let movesStrongPermission = layout.keepsStrongPermissionVisible && isStrongPermissionSelected
                    let movesSettingsMenu = dynamicTypeSize.isAccessibilitySize || !isStrongPermissionSelected
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            leadingControls(
                                layout: layout,
                                movesStrongPermissionToWrappedRow: movesStrongPermission,
                                movesSettingsMenuToWrappedRow: movesSettingsMenu
                            )
                        }
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 58 : 34)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: controlSpacing) {
                                if movesSettingsMenu { moreSettingsMenu }
                                if movesStrongPermission { permissionMenu }
                                Spacer(minLength: 0)
                                if showsProjectSelector { projectSelector(iconOnly: layout.showsProjectIconOnly) }
                                actionButtons
                            }
                        }
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 58 : 34)
                    }
                }
            } else {
                HStack(spacing: controlSpacing) {
                    leadingControls(layout: layout)
                    Spacer(minLength: 0)
                    if showsProjectSelector { projectSelector(iconOnly: layout.showsProjectIconOnly) }
                    actionButtons
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 60 : 36)
    }

    private var controlSpacing: CGFloat { dynamicTypeSize.isAccessibilitySize ? 6 : 3 }

    private func leadingControls(
        layout: DSInputBarLayout,
        movesStrongPermissionToWrappedRow: Bool = false,
        movesSettingsMenuToWrappedRow: Bool = false
    ) -> some View {
        HStack(spacing: controlSpacing) {
            photoPickerButton
            if let model { modelChip(model) }
            if layout.mergesSettings {
                if !movesSettingsMenuToWrappedRow,
                   showsEffortChip || (showsPermissionChip && !isStrongPermissionSelected) {
                    moreSettingsMenu
                }
                if isStrongPermissionSelected && !movesStrongPermissionToWrappedRow { permissionMenu }
            } else {
                if showsEffortChip { effortMenu }
                if showsPermissionChip { permissionMenu }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var photoPickerButton: some View {
        smallControlButton(label: "画像を添付", fill: DSColor.fillSubtle) {
            Image(systemName: "plus")
                .font(DSFont.inputBar(.addSymbol, for: dynamicTypeSize).weight(.medium))
                .foregroundStyle(IOSColor.text.primary)
        } action: {
            if attachmentStrip.count >= maxAttachments {
                onAttachmentLimitReached?()
            } else {
                openPhotoPicker()
            }
        }
    }

    private func modelChip(_ model: (kind: AgentKind, displayName: String)) -> some View {
        smallControlButton(label: "モデル、\(model.displayName)", fill: IOSColor.bg.chip) {
            HStack(spacing: 4) {
                DSAgentBrandIcon(kind: model.kind, size: dynamicTypeSize.isAccessibilitySize ? 26 : 15)
                Text(model.displayName)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(DSFont.inputBar(.chevron, for: dynamicTypeSize).weight(.semibold))
                    .foregroundStyle(IOSColor.text.secondary)
            }
            .font(DSFont.inputBar(.chip, for: dynamicTypeSize).weight(.semibold))
            .foregroundStyle(IOSColor.text.primary)
        } action: {
            onSelectModel?()
        }
        .layoutPriority(1)
    }

    private var effortMenu: some View {
        Menu {
            Section("思考の強さ") {
                ForEach(settings?.effortOptions ?? []) { option in
                    Button { settings?.onSelectEffort(option.value) } label: {
                        optionMenuLabel(option, isSelected: option.value == settings?.selectedEffort)
                    }
                }
            }
            Section {
                if settings?.selectedEffort == nil,
                   !(settings?.effortOptions.contains(where: { $0.value == nil }) ?? false) {
                    Label("既定", systemImage: "checkmark")
                }
                Text("モデルを変えると、そのモデルの既定の強さに戻ります")
            }
        } label: {
            settingChip(
                symbol: "gauge.medium",
                title: currentEffortName,
                label: "思考の強さ、\(currentEffortName)",
                isUpdating: settings?.isUpdatingEffort == true
            )
        }
        .disabled(settings?.isUpdatingEffort == true || settings?.isUpdatingPermission == true)
    }

    private var permissionMenu: some View {
        Menu {
            Section("権限 · \(settings?.agentName ?? "")") {
                if settings?.selectedPermission == nil,
                   !(settings?.permissionOptions.contains(where: { $0.value == nil }) ?? false) {
                    Label("既定", systemImage: "checkmark")
                }
                ForEach(settings?.permissionOptions ?? []) { option in
                    Button {
                        if Self.isStrongPermissionValue(option.value ?? "") {
                            pendingDangerousPermission = option
                        } else {
                            settings?.onSelectPermission(option.value)
                        }
                    } label: {
                        optionMenuLabel(
                            option,
                            isSelected: option.value == settings?.selectedPermission && settings?.planMode == false,
                            isDanger: Self.isStrongPermissionValue(option.value ?? "")
                        )
                    }
                }
            }
            if settings?.planModeAvailable == true {
                Section {
                    Button { settings?.onSelectPlanMode(true) } label: {
                        HStack {
                            Text("Plan")
                            Spacer()
                            if settings?.planMode == true { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section {
                Text("確認なしで全部を許す権限は、選ぶときに確認します。実行中に変えたときは次の指示から効きます")
            }
        } label: {
            settingChip(
                symbol: "shield",
                title: currentPermissionName,
                label: isStrongPermissionSelected
                    ? "権限、\(currentPermissionName)。確認なしで全部を許可しています"
                    : "権限、\(currentPermissionName)",
                isUpdating: settings?.isUpdatingPermission == true || settings?.isUpdatingPlanMode == true,
                isDanger: isStrongPermissionSelected
            )
        }
        .disabled(settings?.isUpdatingEffort == true || settings?.isUpdatingPermission == true || settings?.isUpdatingPlanMode == true)
    }

    private var moreSettingsMenu: some View {
        Menu {
            if showsEffortChip {
                Menu {
                    effortMenuContents
                } label: {
                    overflowMenuRow(title: "思考の強さ", value: currentEffortName, symbol: "gauge.medium")
                }
            }
            if showsPermissionChip && !isStrongPermissionSelected {
                Menu {
                    permissionMenuContents
                } label: {
                    overflowMenuRow(title: "権限", value: currentPermissionName, symbol: "shield")
                }
            }
        } label: {
            smallControlButton(label: "思考の強さと権限を変更", fill: DSColor.fillSubtle) {
                Image(systemName: "ellipsis")
                    .font(DSFont.inputBar(.moreSymbol, for: dynamicTypeSize).weight(.semibold))
                    .foregroundStyle(IOSColor.text.primary)
            } action: {}
        }
        .disabled(settings?.isUpdatingEffort == true || settings?.isUpdatingPermission == true || settings?.isUpdatingPlanMode == true)
    }

    private var effortMenuContents: some View {
        Group {
            Section("思考の強さ") {
                ForEach(settings?.effortOptions ?? []) { option in
                    Button { settings?.onSelectEffort(option.value) } label: {
                        optionMenuLabel(option, isSelected: option.value == settings?.selectedEffort)
                    }
                }
            }
            Section {
                if settings?.selectedEffort == nil,
                   !(settings?.effortOptions.contains(where: { $0.value == nil }) ?? false) {
                    Label("既定", systemImage: "checkmark")
                }
                Text("モデルを変えると、そのモデルの既定の強さに戻ります")
            }
        }
    }

    private var permissionMenuContents: some View {
        Group {
            Section("権限 · \(settings?.agentName ?? "")") {
                if settings?.selectedPermission == nil,
                   !(settings?.permissionOptions.contains(where: { $0.value == nil }) ?? false) {
                    Label("既定", systemImage: "checkmark")
                }
                ForEach(settings?.permissionOptions ?? []) { option in
                    Button {
                        if Self.isStrongPermissionValue(option.value ?? "") {
                            pendingDangerousPermission = option
                        } else {
                            settings?.onSelectPermission(option.value)
                        }
                    } label: {
                        optionMenuLabel(
                            option,
                            isSelected: option.value == settings?.selectedPermission && settings?.planMode == false,
                            isDanger: Self.isStrongPermissionValue(option.value ?? "")
                        )
                    }
                }
            }
            if settings?.planModeAvailable == true {
                Section {
                    Button { settings?.onSelectPlanMode(true) } label: {
                        HStack {
                            Text("Plan")
                            Spacer()
                            if settings?.planMode == true { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section {
                Text("確認なしで全部を許す権限は、選ぶときに確認します。実行中に変えたときは次の指示から効きます")
            }
        }
    }

    private func optionMenuLabel(
        _ option: DSInputBarSettingOption,
        isSelected: Bool,
        isDanger: Bool = false
    ) -> some View {
        HStack(spacing: DSSpacing.s) {
            Text(option.displayName)
            if isDanger {
                Text("確認あり")
                    .font(.caption)
                    .foregroundStyle(IOSColor.status.error)
            }
            Spacer(minLength: 4)
            if isSelected { Image(systemName: "checkmark") }
        }
        .foregroundStyle(isDanger ? IOSColor.status.error : IOSColor.text.primary)
        .accessibilityLabel(isDanger ? "\(option.displayName)、確認あり" : option.displayName)
    }

    private func overflowMenuRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: symbol)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(IOSColor.text.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(IOSColor.text.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var showsProjectSelector: Bool {
        mode == .newChat && (projectName != nil || onSelectProject != nil || onSelectProjectID != nil)
    }

    private func projectSelector(iconOnly: Bool) -> some View {
        Menu {
            Section("プロジェクト") {
                if projectOptions.isEmpty {
                    Button("プロジェクトがありません") {}
                        .disabled(true)
                } else {
                    ForEach(projectOptions) { option in
                        Button {
                            if let onSelectProjectID { onSelectProjectID(option.id) }
                            else { onSelectProject?() }
                        } label: {
                            HStack(spacing: DSSpacing.s) {
                                if option.id == selectedProjectID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(IOSColor.accent)
                                }
                                Text(option.name)
                                Spacer(minLength: DSSpacing.s)
                                if option.isLastUsed {
                                    Text("前回使った")
                                        .font(DSFont.caption)
                                        .foregroundStyle(IOSColor.text.secondary)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(DSFont.inputBar(.chipSymbol, for: dynamicTypeSize))
                if !iconOnly {
                    Text(projectName ?? "プロジェクト")
                        .font(DSFont.inputBar(.chip, for: dynamicTypeSize))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(DSFont.inputBar(.chevron, for: dynamicTypeSize).weight(.semibold))
            }
            .foregroundStyle(projectName == nil ? IOSColor.text.secondary : IOSColor.text.primary)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 7)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 58 : 34)
            .background(DSColor.fillSubtle, in: Capsule())
            .fixedSize()
            .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityLabel("プロジェクト、\(projectName ?? "未選択")")
    }

    private func settingChip(
        symbol: String,
        title: String,
        label: String,
        isUpdating: Bool,
        isDanger: Bool = false
    ) -> some View {
        smallControlButton(label: label, fill: DSColor.fillSubtle) {
            HStack(spacing: 4) {
                if isUpdating {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: symbol)
                        .font(DSFont.inputBar(.chipSymbol, for: dynamicTypeSize).weight(.medium))
                }
                Text(title)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(DSFont.inputBar(.chip, for: dynamicTypeSize).weight(.medium))
            .foregroundStyle(isDanger ? IOSColor.status.error : IOSColor.text.primary)
        } action: {}
    }

    private func smallControlButton<Label: View>(
        label: String,
        fill: Color,
        @ViewBuilder content: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .fixedSize()
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 7)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 58 : 34)
                .background(fill, in: Capsule())
                .frame(
                    minWidth: dynamicTypeSize.isAccessibilitySize ? 58 : 34,
                    minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 34
                )
                .fixedSize()
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityLabel(label)
    }

    private var actionButtons: some View {
        HStack(spacing: controlSpacing) {
            if actionState.showsStop {
                stopButton.transition(actionButtonTransition)
            }
            if actionState.showsSend {
                sendButton.transition(actionButtonTransition)
            }
        }
        .animation(reduceMotion ? DSMotion.quick : DSMotion.spring, value: actionState)
    }

    private var actionButtonTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(IOSColor.text.secondary)
                } else {
                    Image(systemName: Self.sendButtonIconName)
                        .font(DSFont.inputBar(.sendSymbol, for: dynamicTypeSize).weight(.semibold))
                }
            }
            .foregroundStyle(actionState.sendIsEnabled ? IOSColor.accentOnFill : IOSColor.text.secondary)
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 58 : 34,
                height: dynamicTypeSize.isAccessibilitySize ? 58 : 34
            )
            .background(actionState.sendIsEnabled ? IOSColor.accent : DSColor.fillSubtle, in: Circle())
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 58 : 34,
                height: dynamicTypeSize.isAccessibilitySize ? 58 : 34
            )
            .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(DSPressFeedbackStyle())
        .disabled(!actionState.sendIsEnabled)
        .accessibilityLabel(Text(isLoading ? "送信中" : Self.sendAccessibilityLabel))
    }

    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: Self.stopButtonIconName)
                .font(DSFont.inputBar(.stopSymbol, for: dynamicTypeSize).weight(.semibold))
                .foregroundStyle(.white)
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 58 : 34,
                    height: dynamicTypeSize.isAccessibilitySize ? 58 : 34
                )
                .background(IOSColor.stop, in: Circle())
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 58 : 34,
                    height: dynamicTypeSize.isAccessibilitySize ? 58 : 34
                )
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(DSPressFeedbackStyle())
        .accessibilityLabel(Text(Self.stopAccessibilityLabel))
    }

    private func submit() {
        guard actionState.sendIsEnabled else { return }
        onSubmit()
    }

    private func openPhotoPicker() {
        #if os(iOS)
            guard onAddAttachments != nil else { return }
            selectedPhotoItems = []
            // PhotosPicker presentation is driven by the button below.
            isPhotoPickerPresented = true
        #endif
    }

    #if os(iOS)
        @State private var isPhotoPickerPresented = false

        private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
            defer { selectedPhotoItems = [] }
            guard let onAddAttachments else { return }
            var imported: [Result<SendAttachment, Error>] = []
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        imported.append(.failure(ImageAttachmentPreparationError.invalidImage))
                        continue
                    }
                    imported.append(.success(SendAttachment(mediaType: "application/octet-stream", data: data)))
                } catch {
                    imported.append(.failure(error))
                }
            }
            if !imported.isEmpty { onAddAttachments(imported) }
        }
    #endif
}

/// UTF-16 カーソル位置の正規化と公開タイミング（プラットフォーム非依存・白箱テスト対象）。
enum DSInputCursorMath {
    static func clampedCursorUTF16(_ cursorUTF16: Int, textUTF16Count: Int) -> Int {
        max(0, min(cursorUTF16, textUTF16Count))
    }

    static func normalizedCursorIfNeeded(_ cursorUTF16: Int, textUTF16Count: Int) -> Int? {
        let clamped = clampedCursorUTF16(cursorUTF16, textUTF16Count: textUTF16Count)
        return clamped == cursorUTF16 ? nil : clamped
    }

    static func shouldPublishSelectionOffset(_ selectionUTF16: Int, boundCursorUTF16: Int) -> Bool {
        selectionUTF16 != boundCursorUTF16
    }

    static func shouldPushSelection(cursorUTF16: Int, lastPushedCursorUTF16: Int) -> Bool {
        cursorUTF16 != lastPushedCursorUTF16
    }

    static func isSelectionValid(_ range: Range<String.Index>, in text: String) -> Bool {
        utf16Offset(of: range.lowerBound, in: text) != nil
            && utf16Offset(of: range.upperBound, in: text) != nil
    }

    static func utf16Offset(of index: String.Index, in text: String) -> Int? {
        guard index == text.endIndex || text.indices.contains(index) else { return nil }
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }
}

private struct DSInputBarWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
