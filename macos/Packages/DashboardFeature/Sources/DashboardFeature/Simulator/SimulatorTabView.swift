import AgentDomain
import AppKit
import DesignSystem
import SimulatorBridgeKit
import SwiftUI

public struct SimulatorTabView: View {
    private let hub: SimulatorHub
    private let sessionID: SessionID
    private let isFocused: Bool
    @State private var displayID = UUID()
    @State private var windowVisible = false
    @State private var isPresented = false
    @State private var menuFocusRequest = 0
    @State private var preservesScreenFocus = false
    @State private var sendsKeys = false
    @State private var confirmsShutdown = false
    @State private var shutdownUDID: String?
    @State private var screenshotReason: String?

    public init(hub: SimulatorHub, sessionID: SessionID, isFocused: Bool) {
        self.hub = hub
        self.sessionID = sessionID
        self.isFocused = isFocused
    }

    private var device: SimulatorDevice? { hub.selectedDevice(for: sessionID) }
    private var connection: SimulatorDisplayConnection? { hub.connection(for: sessionID) }

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 8) {
                    SimulatorDeviceMenu(devices: hub.devices, selected: device?.udid,
                                        compact: geometry.size.width < 450,
                                        focusRequest: menuFocusRequest,
                                        preservesScreenFocus: preservesScreenFocus,
                                        failed: { screenshotReason = $0 }) { udid in
                        sendsKeys = false
                        hub.select(udid: udid, for: sessionID)
                    }
                    .accessibilityIdentifier("simulator-device-menu")
                    .fixedSize()
                    .layoutPriority(2)
                    if let device, device.state == "Shutdown" {
                        Button("起動") { Task { await hub.boot(for: sessionID) } }
                            .accessibilityIdentifier("simulator-boot")
                    }
                    if sendsKeys {
                        Text(geometry.size.width < 450 ? "→ 端末" : "キー入力を端末に送信中（⌘Esc で解除）")
                            .font(DSFont.meta)
                            .foregroundStyle(DSColor.textSecondary)
                            .lineLimit(1)
                            .accessibilityLabel("キー入力を端末に送信中（⌘Esc で解除）")
                    }
                    Spacer(minLength: 0)
                    Button { connection?.sendHome() } label: { Image(systemName: "house") }
                        .help("ホーム（⇧⌘H）")
                        .accessibilityLabel("ホーム")
                        .accessibilityIdentifier("simulator-home")
                        .disabled(connection?.displayInfo == nil)
                    Button { Task { await takeScreenshot() } } label: { Image(systemName: "camera") }
                        .help("スクリーンショットを Finder で表示")
                        .accessibilityLabel("スクリーンショット")
                        .disabled(device?.isBooted != true)
                    Button {
                        shutdownUDID = device?.udid
                        confirmsShutdown = true
                    } label: { Image(systemName: "stop") }
                        .help("端末を停止")
                        .accessibilityLabel("端末を停止")
                        .accessibilityIdentifier("simulator-shutdown")
                        .disabled(device?.isBooted != true)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .frame(height: 30)
            }
            .frame(height: 30)
            Divider()
            if let reason = screenshotReason ?? hub.operationReason ?? hub.listingReason ?? connection?.reason {
                Text(verbatim: reason).font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary).padding(8)
            }
            if let info = connection?.displayInfo {
                SimulatorScreenView(displayInfo: info, connection: connection,
                                    isVisible: windowVisible,
                                    releaseFocus: { requestMenuFocus() },
                                    deviceName: device?.name ?? "端末",
                                    inputFocusChanged: { focused in
                                        Task { @MainActor in sendsKeys = focused }
                                    })
                    .overlay {
                        if sendsKeys {
                            GeometryReader { geometry in
                                if let rect = SimulatorInputMapper.displayRect(
                                    in: CGRect(origin: .zero, size: geometry.size),
                                    pixelSize: CGSize(width: info.pixelWidth, height: info.pixelHeight)
                                ) {
                                    Rectangle().stroke(DSColor.focusRing, lineWidth: 2)
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone").font(.system(size: 32))
                    Text(device == nil ? "端末がありません" : connection?.reason != nil ? "画面を取得できません" : device?.isBooted == true ? "画面を取得しています" : device?.state == "Booting" ? "端末を起動しています" : "端末を起動すると画面が表示されます")
                        .font(DSFont.auxiliary)
                }
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(NSWorkspace.shared.isVoiceOverEnabled
                 ? "端末内を読み上げるには Simulator.app で開き、iOS の VoiceOver を使います"
                 : sendsKeys ? "⌘ 付きのキーは Phlox が受けます · ⌘Esc で解除"
                 : "キー入力はまだ送っていません · 画面をクリックすると送ります")
                .font(DSFont.meta).foregroundStyle(DSColor.textSecondary).padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-tab")
        .background(SimulatorWindowVisibility { visible in
            windowVisible = visible
            hub.setVisible(visible && isPresented, displayID: displayID, sessionID: sessionID)
            if !visible { sendsKeys = false }
        })
        .background {
            if isFocused {
                Button("ホーム") { connection?.sendHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            isPresented = true
            hub.setVisible(windowVisible, displayID: displayID, sessionID: sessionID)
            if isFocused { requestMenuFocus() }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { requestMenuFocus(preservingScreenFocus: true) }
        }
        .onChange(of: hub.menuFocusRevision(for: sessionID)) { _, _ in
            if isFocused { requestMenuFocus() }
        }
        .onDisappear {
            isPresented = false
            hub.setVisible(false, displayID: displayID, sessionID: sessionID)
        }
        .dsDialog(isPresented: $confirmsShutdown) {
            DSDialog(.recoverable, title: "端末を停止しますか？",
                     message: "この端末を表示中の他のタブ・Phlox の別の版・Simulator.app にも影響します",
                     buttons: [
                        DSDialogButton("停止") {
                            let udid = shutdownUDID
                            confirmsShutdown = false
                            shutdownUDID = nil
                            if let udid { Task { await hub.shutdown(udid: udid) } }
                        },
                        DSDialogButton("キャンセル", role: .primary) {
                            confirmsShutdown = false
                            shutdownUDID = nil
                        },
                     ], onCancel: {
                        confirmsShutdown = false
                        shutdownUDID = nil
                     }) { EmptyView() }
        }
    }

    private func requestMenuFocus(preservingScreenFocus: Bool = false) {
        preservesScreenFocus = preservingScreenFocus
        menuFocusRequest += 1
    }

    private func takeScreenshot() async {
        screenshotReason = nil
        do {
            let folder = try FileManager.default.url(for: .picturesDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("Phlox Simulator", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("Simulator-\(UUID().uuidString).png")
            if await hub.screenshot(for: sessionID, destination: destination) {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch {
            screenshotReason = "スクリーンショットを保存できません: \(error.localizedDescription)"
        }
    }
}

struct SimulatorDeviceMenu: NSViewRepresentable {
    let devices: [SimulatorDevice]
    let selected: String?
    let compact: Bool
    let focusRequest: Int
    let preservesScreenFocus: Bool
    let failed: (String) -> Void
    let select: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(select: select, failed: failed) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.cell?.lineBreakMode = .byClipping
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setAccessibilityIdentifier("simulator-device-menu")
        button.setAccessibilityLabel("端末の選択")
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.select = select
        context.coordinator.failed = failed
        context.coordinator.configure(button, devices: devices, selected: selected, compact: compact)
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            let preserve = preservesScreenFocus
            let current = focusRequest
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                guard coordinator.focusRequest == current else { return }
                Coordinator.focus(button, preservingScreenFocus: preserve)
            }
        }
    }
    @MainActor final class Coordinator: NSObject {
        var select: (String?) -> Void
        var failed: (String) -> Void
        var focusRequest = 0
        private var devices: [SimulatorDevice]?
        private var selected: String?
        private var compact = false
        init(select: @escaping (String?) -> Void, failed: @escaping (String) -> Void) {
            self.select = select
            self.failed = failed
        }
        func configure(_ button: NSPopUpButton, devices: [SimulatorDevice], selected: String?, compact: Bool = false) {
            let rebuildsMenu = self.devices != devices || self.compact != compact
            guard rebuildsMenu || self.selected != selected else { return }
            if rebuildsMenu {
                button.removeAllItems()
                for device in devices {
                    let runtime = device.runtimeIdentifier.components(separatedBy: "iOS-").last?.replacingOccurrences(of: "-", with: ".") ?? ""
                    let state = device.isBooted ? "起動済み" : device.state == "Booting" ? "起動中" : "停止中"
                    button.addItem(withTitle: compact ? device.name : "\(device.name) · iOS \(runtime) · \(state)")
                    button.lastItem?.representedObject = device.udid
                }
                if devices.isEmpty {
                    button.addItem(withTitle: "端末なし")
                    button.lastItem?.isEnabled = false
                }
                button.menu?.addItem(.separator())
                button.addItem(withTitle: "Simulator.app で開く")
                button.lastItem?.representedObject = "Simulator.app"
                self.devices = devices
                self.compact = compact
            }
            self.selected = selected
            restoreSelection(button)
            if let device = devices.first(where: { $0.udid == selected }) {
                let state = device.isBooted ? "起動済み" : device.state == "Booting" ? "起動中" : "停止中"
                button.setAccessibilityLabel("端末の選択: \(device.name)、\(state)")
            } else {
                button.setAccessibilityLabel("端末の選択: 端末なし")
            }
        }

        func restoreSelection(_ button: NSPopUpButton) {
            if let index = devices?.firstIndex(where: { $0.udid == selected }) {
                button.selectItem(at: index)
            } else {
                button.selectItem(at: 0)
            }
        }
        static func focus(_ button: NSPopUpButton, preservingScreenFocus: Bool) {
            guard !(preservingScreenFocus && button.window?.firstResponder is SimulatorScreenNSView) else { return }
            button.window?.makeFirstResponder(button)
        }
        @objc func changed(_ button: NSPopUpButton) {
            button.window?.makeFirstResponder(button)
            let value = button.selectedItem?.representedObject as? String
            if value == "Simulator.app" {
                restoreSelection(button)
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
                        if let error {
                            Task { @MainActor in self?.failed("Simulator.app を開けません: \(error.localizedDescription)") }
                        }
                    }
                } else {
                    failed("Simulator.app が見つかりません")
                }
            } else {
                select(value)
            }
        }
    }
}

struct SimulatorWindowVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { VisibilityView() }
    func updateNSView(_ view: VisibilityView, context: Context) { view.changed = changed }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stop() }

    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        private var revision = 0
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(updateVisibility), name: name, object: window)
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(updateVisibility), name: name, object: nil)
            }
            updateVisibility()
        }
        override func viewDidHide() { super.viewDidHide(); updateVisibility() }
        override func viewDidUnhide() { super.viewDidUnhide(); updateVisibility() }
        @objc private func updateVisibility() {
            revision += 1
            let current = revision
            let visible = window.map {
                $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
            } == true && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == current else { return }
                self.changed?(visible)
            }
        }
        func stop() {
            revision += 1
            NotificationCenter.default.removeObserver(self)
            // SwiftUI の破棄処理中に、そのビューの State へ書き戻さない。
            let notify = changed
            changed = nil
            DispatchQueue.main.async { notify?(false) }
        }
    }
}
