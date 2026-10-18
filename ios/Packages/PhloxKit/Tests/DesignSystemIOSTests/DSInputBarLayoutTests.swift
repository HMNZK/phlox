import Foundation
import Testing
@testable import DesignSystemIOS

@MainActor
@Suite("入力欄の幅と圧縮")
struct DSInputBarLayoutTests {
    @Test("428pt のセッションは設定チップを分けて表示する")
    func session428KeepsSettingsSeparate() {
        let layout = resolve(
            width: 404,
            mode: .session,
            effort: "高",
            permission: "Accept Edits"
        )

        #expect(!layout.mergesSettings)
        #expect(!layout.wrapsSecondRow)
    }

    @Test("428pt の Codex 詳細は「中」のチップを権限と分けて表示する")
    func codexDetail428KeepsMediumEffortChipSeparate() {
        let layout = resolve(
            width: 404,
            mode: .session,
            modelName: "gpt-6.1-sol",
            effort: "中",
            permission: "Default"
        )

        #expect(!layout.mergesSettings)
        #expect(!layout.wrapsSecondRow)
    }

    @Test("428pt の実行中・本文ありでも Accept Edits を省略しない")
    func runningReply428KeepsFullAcceptEditsChip() {
        let layout = resolve(
            width: 404,
            mode: .session,
            effort: "高",
            permission: "Accept Edits",
            hasText: true,
            isRunning: true
        )

        #expect(!layout.mergesSettings)
        #expect(!layout.wrapsSecondRow)
    }

    @Test("375pt のセッションは思考の強さと権限をまとめる")
    func session375MergesSettings() {
        let layout = resolve(
            width: 351,
            mode: .session,
            effort: "高",
            permission: "Accept Edits"
        )

        #expect(layout.mergesSettings)
        #expect(!layout.wrapsSecondRow)
    }

    @Test("Dynamic Type 最大は最初から設定をまとめる")
    func accessibilitySizeStartsMerged() {
        let layout = resolve(
            width: 404,
            mode: .session,
            isAccessibilitySize: true,
            effort: "高",
            permission: "Accept Edits"
        )

        #expect(layout.mergesSettings)
        #expect(!layout.wrapsSecondRow)
    }

    @Test("428pt の新規チャットでも Accept Edits は設定をまとめる")
    func draft428MergesSettingsBeforeProjectCompression() {
        let layout = resolve(
            width: 408,
            mode: .newChat,
            effort: "高",
            permission: "Accept Edits",
            hasProject: true,
            projectName: "Phlox"
        )

        #expect(layout.mergesSettings)
        #expect(!layout.showsProjectIconOnly)
    }

    @Test("強い権限は幅が足りなくても設定メニューへ隠さない")
    func strongPermissionStaysVisibleWhenCompressed() {
        let layout = resolve(
            width: 240,
            mode: .session,
            effort: "高",
            permission: "Full Access",
            isStrongPermission: true
        )

        #expect(layout.mergesSettings)
        #expect(layout.keepsStrongPermissionVisible)
        #expect(layout.wrapsSecondRow)
    }

    @Test("428pt の強い権限は赤いチップを保つ")
    func strongPermissionFitsAt428Points() {
        let layout = resolve(
            width: 404,
            mode: .session,
            effort: "高",
            permission: "Bypass Permissions",
            isStrongPermission: true
        )

        #expect(!layout.mergesSettings)
        #expect(!layout.wrapsSecondRow)
        #expect(layout.keepsStrongPermissionVisible)
    }

    @Test("強い権限は表示名でなく Mac の値で判定する")
    func dangerousPermissionClassificationUsesWireValue() {
        #expect(DSInputBar.isStrongPermissionValue("bypassPermissions"))
        #expect(DSInputBar.isStrongPermissionValue(":danger-full-access"))
        #expect(!DSInputBar.isStrongPermissionValue("Bypass Permissions"))
        #expect(!DSInputBar.isStrongPermissionValue("Full Access"))
    }

    private func resolve(
        width: CGFloat,
        mode: DSInputBarMode,
        isAccessibilitySize: Bool = false,
        modelName: String = "Sonnet 5",
        effort: String?,
        permission: String?,
        isStrongPermission: Bool = false,
        hasProject: Bool = false,
        projectName: String? = nil,
        hasText: Bool = false,
        isRunning: Bool = false
    ) -> DSInputBarLayout {
        DSInputBarLayout.resolve(
            width: width,
            mode: mode,
            isAccessibilitySize: isAccessibilitySize,
            hasModel: true,
            modelName: modelName,
            effortName: effort,
            permissionName: permission,
            isStrongPermission: isStrongPermission,
            hasText: hasText,
            isRunning: isRunning,
            hasProject: hasProject,
            projectName: projectName
        )
    }
}
