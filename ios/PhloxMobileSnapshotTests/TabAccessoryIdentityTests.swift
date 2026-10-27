import DesignSystemIOS
import SwiftUI
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct TabAccessoryIdentityTests {
    @Test(arguments: AccessoryHarnessMode.allCases)
    func togglingAccessoryPreservesEditsAndDoesNotRestartContent(mode: AccessoryHarnessMode) async throws {
        let state = AccessoryHarnessState()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: AccessoryIdentityHarness(state: state, mode: mode))
        defer {
            window.isHidden = true
            window.rootViewController = nil
            if let previous, !previous.isHidden { previous.makeKey() }
        }
        window.makeKeyAndVisible()
        try await waitForAccessoryHarness {
            state.startedTokens.count == 1 && accessoryEditButton(in: window) != nil
        }
        let token = try #require(state.startedTokens.first)
        let editButton = try #require(accessoryEditButton(in: window))
        editButton.sendActions(for: .touchUpInside)
        try await waitForAccessoryHarness { accessoryEditButton(in: window)?.title(for: .normal) == "編集 1" }

        for enabled in [true, false, true, false] {
            state.accessoryEnabled = enabled
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
            #expect(state.startedTokens == [token], "対応待ちバーの切替で取得 task を再開しない")
            #expect(accessoryEditButton(in: window)?.title(for: .normal) == "編集 1", "入力中の状態を保持する")
        }

        let retainedButton = try #require(accessoryEditButton(in: window))
        retainedButton.sendActions(for: .touchUpInside)
        try await waitForAccessoryHarness { accessoryEditButton(in: window)?.title(for: .normal) == "編集 2" }
    }
}

enum AccessoryHarnessMode: CaseIterable, Sendable {
    case platformTabs
    case safeAreaInset
}

@MainActor
@Observable
private final class AccessoryHarnessState {
    var accessoryEnabled = false
    var selection = 0
    var startedTokens: [UUID] = []
}

@MainActor
private struct AccessoryIdentityHarness: View {
    @Bindable var state: AccessoryHarnessState
    let mode: AccessoryHarnessMode

    var body: some View {
        switch mode {
        case .platformTabs:
            DSPlatformTabView(selection: $state.selection, actionValue: 2, accessoryEnabled: state.accessoryEnabled) {
                Tab("セッション", systemImage: "list.bullet", value: 0) {
                    AccessoryEditableContent(state: state)
                }
                Tab("設定", systemImage: "gearshape", value: 1) {
                    Text("設定")
                }
            } accessory: {
                Text("対応待ち 1")
            }
        case .safeAreaInset:
            DSPlatformTabContent(accessoryEnabled: state.accessoryEnabled, usesNativeAccessory: false) {
                AccessoryEditableContent(state: state)
            } accessory: {
                Text("対応待ち 1")
            }
        }
    }
}

@MainActor
private struct AccessoryEditableContent: View {
    let state: AccessoryHarnessState
    @State private var token = UUID()
    @State private var edits = 0

    var body: some View {
        AccessoryEditButton(edits: $edits)
            .frame(width: 200, height: 60)
            .task { state.startedTokens.append(token) }
    }
}

@MainActor
private struct AccessoryEditButton: UIViewRepresentable {
    @Binding var edits: Int

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "accessory-identity.edit"
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.setTitle("編集 \(edits)", for: .normal)
        button.removeAction(identifiedBy: UIAction.Identifier("edit"), for: .touchUpInside)
        button.addAction(UIAction(identifier: UIAction.Identifier("edit")) { _ in
            edits += 1
        }, for: .touchUpInside)
    }
}

@MainActor
private func accessoryEditButton(in root: UIView) -> UIButton? {
    if let button = root as? UIButton, button.accessibilityIdentifier == "accessory-identity.edit" {
        return button
    }
    return root.subviews.lazy.compactMap { accessoryEditButton(in: $0) }.first
}

@MainActor
private func waitForAccessoryHarness(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            throw NSError(domain: "TabAccessoryIdentityTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "対応待ちバーの操作結果が反映されない"])
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
