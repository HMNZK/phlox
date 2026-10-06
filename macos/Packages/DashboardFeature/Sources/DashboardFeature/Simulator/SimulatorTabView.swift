import AgentDomain
import AppKit
import DesignSystem
import SimulatorBridgeKit
import SwiftUI

public struct SimulatorTabView: View {
    private let hub: SimulatorHub
    private let sessionID: SessionID
    private let isFocused: Bool
    private let tellAgent: ((String) -> Void)?
    @State private var displayID = UUID()
    @State private var windowVisible = false
    @State private var isPresented = false
    @State private var menuFocusRequest = 0
    @State private var preservesScreenFocus = false
    @State private var sendsKeys = false
    @State private var confirmsShutdown = false
    @State private var shutdownUDID: String?
    @State private var screenshotReason: String?
    @State private var showsDiagnostics = false

    public init(hub: SimulatorHub, sessionID: SessionID, isFocused: Bool, tellAgent: ((String) -> Void)? = nil) {
        self.hub = hub
        self.sessionID = sessionID
        self.isFocused = isFocused
        self.tellAgent = tellAgent
    }

    private var device: SimulatorDevice? { hub.selectedDevice(for: sessionID) }
    private var connection: SimulatorDisplayConnection? { hub.connection(for: sessionID) }
    private var support: SimulatorPolicy.Support { hub.support(for: sessionID, displayID: displayID) }
    private var allowsInput: Bool { support.allowsInput && connection?.inputEnabled == true }

    public var body: some View {
        SimulatorTabContent(hub: hub, sessionID: sessionID, displayID: displayID,
                            windowVisible: windowVisible, menuFocusRequest: menuFocusRequest,
                            preservesScreenFocus: preservesScreenFocus,
                            confirmsShutdown: confirmsShutdown,
                            sendsKeys: $sendsKeys, showsDiagnostics: $showsDiagnostics,
                            operationReason: screenshotReason,
                            select: { udid in
                                sendsKeys = false
                                hub.select(udid: udid, for: sessionID)
                            }, releaseFocus: { requestMenuFocus() },
                            screenshot: { Task { await takeScreenshot() } },
                            shutdown: {
                                shutdownUDID = device?.udid
                                confirmsShutdown = true
                            }, openSimulator: openSimulator,
                            tellAgent: tellAgent.map { tell in { if let device { tell(device.agentHint) } } })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("simulator-tab")
        .background(SimulatorWindowVisibility { visible in
            windowVisible = visible
            hub.setVisible(visible && isPresented, displayID: displayID, sessionID: sessionID)
            if !visible { sendsKeys = false }
        })
        .background {
            if isFocused {
                Button("ホーム") { if allowsInput { connection?.sendHome() } }
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
            hub.removeDisplay(displayID)
        }
        .dsDialog(isPresented: $confirmsShutdown) {
            SimulatorShutdownDialog(deviceName: hub.devices.first { $0.udid == shutdownUDID }?.name ?? "端末",
                                    displayCount: shutdownUDID.map { hub.displayCount(udid: $0) } ?? 0,
                                    shutdown: {
                                        let udid = shutdownUDID
                                        cancelShutdown()
                                        if let udid { Task { await hub.shutdown(udid: udid) } }
                                    }, cancel: cancelShutdown)
        }
    }

    private func requestMenuFocus(preservingScreenFocus: Bool = false) {
        preservesScreenFocus = preservingScreenFocus
        menuFocusRequest += 1
    }

    private func cancelShutdown() {
        confirmsShutdown = false
        shutdownUDID = nil
    }

    private func openSimulator() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") else {
            screenshotReason = "Simulator.app が見つかりません"
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        if let device { configuration.arguments = ["-CurrentDeviceUDID", device.udid] }
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in screenshotReason = "Simulator.app を開けません: \(error.localizedDescription)" }
            }
        }
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
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: size.height)
    }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = SimulatorDevicePopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.focusRingType = .none
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
            let groups = [
                ("起動中", devices.filter { $0.isBooted || $0.state == "Booting" }),
                ("停止中", devices.filter { !$0.isBooted && $0.state != "Booting" }),
            ].map { heading, group in
                (heading, group.sorted { lhs, rhs in
                    if (lhs.udid == selected) != (rhs.udid == selected) { return lhs.udid == selected }
                    if lhs.runtimeIdentifier != rhs.runtimeIdentifier {
                        return lhs.runtimeIdentifier.compare(rhs.runtimeIdentifier, options: .numeric) == .orderedDescending
                    }
                    if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
                    return lhs.udid < rhs.udid
                })
            }
            let order = groups.flatMap { $0.1.map(\.udid) }
            let currentOrder = button.itemArray.compactMap { $0.representedObject as? String }
                .filter { $0 != "Simulator.app" }
            let rebuildsMenu = self.devices != devices || self.compact != compact || order != currentOrder
            guard rebuildsMenu || self.selected != selected else { return }
            if rebuildsMenu {
                button.removeAllItems()
                for (heading, group) in groups where !group.isEmpty {
                    let header = NSMenuItem(title: heading, action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    header.attributedTitle = NSAttributedString(string: heading, attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor(DSColor.textTertiary),
                    ])
                    button.menu?.addItem(header)
                    for device in group {
                        let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
                        item.representedObject = device.udid
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 250)]
                        let title = NSMutableAttributedString(string: device.name + "\t" + device.runtimeLabel,
                            attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: paragraph,
                                         .foregroundColor: NSColor(DSColor.textPrimary)])
                        title.addAttributes([.font: NSFont.systemFont(ofSize: 11.5),
                                             .foregroundColor: NSColor(DSColor.textSecondary)],
                                            range: NSRange(location: device.name.utf16.count + 1,
                                                           length: device.runtimeLabel.utf16.count))
                        item.attributedTitle = title
                        item.image = SimulatorDevicePopUpButton.stateImage(device)
                        button.menu?.addItem(item)
                    }
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
            if let custom = button as? SimulatorDevicePopUpButton {
                custom.device = devices.first { $0.udid == selected }
                custom.compact = compact
                custom.invalidateIntrinsicContentSize()
                custom.needsDisplay = true
            }
            restoreSelection(button)
            for item in button.itemArray {
                item.state = item.representedObject as? String == selected && selected != nil ? .on : .off
            }
            if let device = devices.first(where: { $0.udid == selected }) {
                let state = device.stateLabel
                button.setAccessibilityLabel("端末の選択: \(device.name)、\(state)")
                button.toolTip = "\(device.name) · \(device.runtimeLabel) · \(state)"
            } else {
                button.setAccessibilityLabel("端末の選択: 端末なし")
                button.toolTip = "端末なし"
            }
        }

        func restoreSelection(_ button: NSPopUpButton) {
            if let item = button.itemArray.first(where: { $0.representedObject as? String == selected && selected != nil }) {
                button.select(item)
            } else {
                button.select(button.itemArray.first { $0.representedObject is String && $0.representedObject as? String != "Simulator.app" }
                              ?? button.itemArray.first)
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
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
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
