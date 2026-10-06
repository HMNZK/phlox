import AgentDomain
import AppKit
import DesignSystem
import SimulatorBridgeKit
import SwiftUI

/// 状態ごとの表示。接続の寿命と操作の状態はタブが所有する。
struct SimulatorTabContent: View {
    let hub: SimulatorHub
    let sessionID: SessionID
    let displayID: UUID
    var windowVisible = true
    var menuFocusRequest = 0
    var preservesScreenFocus = false
    var confirmsShutdown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var sendsKeys: Bool
    @Binding var showsDiagnostics: Bool
    @State private var menuOperationReason: String?
    var operationReason: String?
    let select: (String?) -> Void
    let releaseFocus: () -> Void
    let screenshot: () -> Void
    let shutdown: () -> Void
    let openSimulator: () -> Void
    var tellAgent: (() -> Void)?

    private var device: SimulatorDevice? { hub.selectedDevice(for: sessionID) }
    private var connection: SimulatorDisplayConnection? { hub.connection(for: sessionID) }
    private var support: SimulatorPolicy.Support { hub.support(for: sessionID, displayID: displayID) }
    private var allowsInput: Bool { support.allowsInput && connection?.inputEnabled == true }
    private var hasScreen: Bool { support.allowsDisplay && connection?.displayInfo != nil }
    private var failureReason: String? { operationReason ?? menuOperationReason ?? hub.operationReason }

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                band(stale: hasScreen && connection?.hasStaleFrame(at: context.date) == true)
            }
            Divider()
            if hasScreen, let reason = failureReason {
                Text(verbatim: reason).font(DSFont.auxiliary)
                    .foregroundStyle(DSColor.textSecondary).padding(8)
            }
            if hasScreen, let info = connection?.displayInfo {
                GeometryReader { geometry in
                    let height = min(max(0, geometry.size.height - 80), max(0, geometry.size.width - 40) * CGFloat(info.pixelHeight) / CGFloat(info.pixelWidth))
                    let width = height * CGFloat(info.pixelWidth) / CGFloat(info.pixelHeight)
                    let radius = width * 0.135
                    VStack(spacing: 12) {
                        SimulatorScreenView(displayInfo: info, connection: connection,
                                            isVisible: windowVisible, releaseFocus: releaseFocus,
                                            deviceName: device?.name ?? "端末",
                                            inputFocusChanged: { focused in
                                                Task { @MainActor in sendsKeys = focused }
                                            }, inputEnabled: allowsInput)
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: radius))
                            .overlay(RoundedRectangle(cornerRadius: radius).inset(by: -0.5)
                                .stroke(DSColor.simulatorScreenEdge, lineWidth: 1))
                            .shadow(color: .black.opacity(DSColor.isDark ? 0.35 : 0.14),
                                    radius: DSColor.isDark ? 12 : 9, y: DSColor.isDark ? 8 : 6)
                            .padding(3)
                            .overlay {
                                if sendsKeys {
                                    RoundedRectangle(cornerRadius: radius + 3).strokeBorder(DSColor.accent, lineWidth: 2)
                                }
                            }
                        Text(hint(compact: geometry.size.width < 450)).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: max(0, geometry.size.width - 40))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                message
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DSColor.isDark ? DSColor.background : DSColor.panelBackground)
    }

    private func hint(compact: Bool) -> String {
        if NSWorkspace.shared.isVoiceOverEnabled {
            return "端末内を読み上げるには Simulator.app で開き、iOS の VoiceOver を使います"
        }
        if support == .displayOnly { return "この組み合わせでは画面の表示だけ有効です" }
        return sendsKeys ? compact ? "⌘ キーは Phlox · ⌘Esc で解除" : "⌘ 付きのキーは Phlox が受けます · ⌘Esc で解除"
            : "キー入力はまだ送っていません · 画面をクリックすると送ります"
    }

    private enum BandDetail { case full, shortText, withoutRuntime, symbols }

    private func band(stale: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            bandContents(stale: stale, detail: .full)
            bandContents(stale: stale, detail: .shortText)
            bandContents(stale: stale, detail: .withoutRuntime)
            bandContents(stale: stale, detail: .symbols)
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 30).background(DSColor.toolbarBackground)
    }

    // 文言、版、印だけの表示の順に縮め、最後に端末名へ残りの幅を渡す。
    @ViewBuilder
    private func bandContents(stale: Bool, detail: BandDetail) -> some View {
        let compact = detail != .full
        let symbolsOnly = detail == .symbols
        HStack(spacing: compact ? 5 : 8) {
            SimulatorDeviceMenu(devices: hub.devices, selected: device?.udid,
                                compact: detail == .withoutRuntime || symbolsOnly, focusRequest: menuFocusRequest,
                                preservesScreenFocus: preservesScreenFocus,
                                failed: { menuOperationReason = $0 }, select: {
                                    menuOperationReason = nil
                                    select($0)
                                })
                .accessibilityIdentifier("simulator-device-menu")
                .fixedSize(horizontal: !symbolsOnly, vertical: true)
                .frame(minWidth: 44)
            if !compact, !stale, support != .unverified {
                Text(device?.stateLabel ?? "停止中").font(DSFont.meta).foregroundStyle(DSColor.textTertiary)
                    .fixedSize()
            }
            if device?.state == "Shutdown" {
                Button("起動") { Task { await hub.boot(for: sessionID) } }
                    .buttonStyle(.ds(.secondary, height: 22, fontSize: 11.5, padding: 8))
                    .fixedSize().layoutPriority(2)
                    .accessibilityIdentifier("simulator-boot")
            }
            if sendsKeys {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                    if !symbolsOnly { Text(compact ? "→ 端末" : "キー入力を端末に送信中") }
                }
                    .font(DSFont.meta).foregroundStyle(DSColor.textPrimary)
                    .padding(.horizontal, compact ? 5 : 7).frame(height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DSColor.accent, lineWidth: 1))
                    .fixedSize().accessibilityLabel("キー入力を端末に送信中")
                    .help("キー入力を端末に送信中")
                    .accessibilityIdentifier("simulator-input-band")
            }
            if support == .displayOnly {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    if !symbolsOnly { Text(compact ? "表示のみ" : "表示のみ（入力は未確認）") }
                }
                    .font(DSFont.meta).foregroundStyle(DSColor.textPrimary).fixedSize()
                    .accessibilityLabel("表示のみ（入力は未確認）")
                    .accessibilityIdentifier("simulator-support-band")
                    .help("入力の動作をまだ確認していない組み合わせです。画面の表示だけ有効にしています。")
            }
            if support == .unverified {
                HStack(spacing: 0) {
                    if symbolsOnly { Image(systemName: "exclamationmark.triangle") }
                    else { Text(compact ? "未確認（このタブのみ）" : "未確認の組み合わせで実行中（このタブのみ）") }
                }
                    .font(DSFont.meta).foregroundStyle(DSColor.textPrimary).fixedSize()
                    .padding(.horizontal, 7).frame(height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DSColor.controlBorder, lineWidth: 1))
                    .accessibilityIdentifier("simulator-support-band")
                    .accessibilityLabel("未確認の組み合わせで実行中（このタブのみ）")
                    .help("未確認の組み合わせで実行中（このタブのみ）")
            }
            if stale {
                HStack(spacing: 5) {
                    HStack(spacing: 5) {
                        Circle().strokeBorder(DSColor.textTertiary, lineWidth: 1).frame(width: 6, height: 6)
                        if !symbolsOnly {
                            Text(compact ? "画面の更新なし" : "しばらく画面の更新を観測していません")
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("しばらく画面の更新を観測していません")
                    .help("しばらく画面の更新を観測していません")
                    Button { showsDiagnostics.toggle() } label: {
                        Image(systemName: "info.circle")
                            .overlay {
                                if showsDiagnostics {
                                    Circle().strokeBorder(DSColor.accent, lineWidth: 1.5).padding(-2)
                                }
                            }
                    }
                        .accessibilityLabel("診断の説明")
                        .accessibilityIdentifier("simulator-diagnostics")
                        .popover(isPresented: $showsDiagnostics) { SimulatorDiagnostics() }
                }.font(DSFont.meta).foregroundStyle(DSColor.textTertiary).fixedSize()
            }
            Spacer(minLength: 0)
            Button { tellAgent?() } label: { Image(systemName: "text.bubble") }
                .buttonStyle(.plain).opacity(canTellAgent ? 1 : 0.45)
                .frame(width: 26, height: 22)
                .fixedSize()
                .help("表示中の端末を入力欄に入れる").accessibilityLabel("エージェントに伝える")
                .accessibilityIdentifier("simulator-tell-agent").disabled(!canTellAgent)
            Button { if allowsInput { connection?.sendHome() } } label: { Image(systemName: "square") }
                .buttonStyle(.plain).opacity(allowsInput ? 1 : 0.45)
                .frame(width: 26, height: 22)
                .fixedSize()
                .help("ホーム（⇧⌘H）").accessibilityLabel("ホーム")
                .accessibilityIdentifier("simulator-home").disabled(!allowsInput)
            Button(action: screenshot) { Image(systemName: "camera") }
                .buttonStyle(.plain).opacity(device?.isBooted == true ? 1 : 0.45)
                .frame(width: 26, height: 22)
                .fixedSize()
                .help("スクリーンショットを Finder で表示").accessibilityLabel("スクリーンショット")
                .accessibilityIdentifier("simulator-screenshot")
                .disabled(device?.isBooted != true)
            Button(action: shutdown) {
                Image(systemName: "stop.fill").frame(width: 26, height: 22)
            }
                .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: 5,
                    baseFill: confirmsShutdown ? DSColor.fillSelected : .clear))
                .fixedSize()
                .help("端末を停止").accessibilityLabel("端末を停止")
                .accessibilityIdentifier("simulator-shutdown").disabled(device?.isBooted != true)
        }
        .buttonStyle(.borderless).font(DSFont.auxiliary)
        .foregroundStyle(DSColor.textSecondary)
        .frame(height: 30)
    }

    private var canTellAgent: Bool { tellAgent != nil && device != nil }

    private var isUnverified: Bool {
        connection?.capability != nil && connection?.blocksRetry != true && support == .unsupported
    }
    private var missingXcode: Bool { hub.listingReason == "Xcode が見つかりません" }
    private var incompatibleProtocol: Bool {
        connection?.capability.map { $0.protocolVersion != SimulatorBridgeInterfaces.protocolVersion } == true
    }

    private var title: String {
        if failureReason != nil { return "操作を完了できません" }
        if missingXcode { return "Xcode が見つかりません" }
        if hub.listingReason != nil { return "端末一覧を取得できません" }
        if incompatibleProtocol { return "Phlox を再起動してください" }
        if isUnverified { return "この組み合わせはまだ動作を確認していません" }
        if connection?.canReconnect == true { return "シミュレーターの補助プロセスに接続できません" }
        if connection?.reason != nil { return "画面取得の部品を読み込めません" }
        guard let device else { return "端末がありません" }
        return device.isBooted ? "画面を取得しています" : device.state == "Booting"
            ? "\(device.name) を起動しています" : "\(device.name) は停止しています"
    }

    private var explanation: String {
        if let reason = failureReason { return reason }
        if missingXcode { return "シミュレーターを表示するには Xcode が必要です。Xcode を入れたあと、もう一度確認してください。" }
        if let reason = hub.listingReason {
            return reason.hasPrefix("端末一覧を取得できません: ")
                ? String(reason.dropFirst("端末一覧を取得できません: ".count)) : reason
        }
        if incompatibleProtocol { return "アプリの更新のあと、古い版の補助プロセスにつながっています。再起動すると新しい版でつながります。" }
        if isUnverified { return "表示や操作が正しく動かないことがあります。試す場合は、このタブだけで有効になります。" }
        if connection?.canReconnect == true { return "自動で 1 回つなぎ直しましたが、応答がありませんでした。作業中のセッションには影響していません。端末は動いたままです。" }
        if let reason = connection?.reason { return reason }
        if device?.state == "Booting" { return "初回の起動は 1 分ほどかかることがあります。" }
        if device?.state == "Shutdown" { return "起動すると、ここに画面を表示します。Simulator.app は開きません。" }
        return "帯の端末メニューから、表示する端末を選びます。"
    }

    private var message: some View {
        VStack(spacing: 10) {
            if device?.state == "Booting" || (device?.isBooted == true && connection?.reason == nil && !isUnverified) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(DSColor.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1) * 360))
                }.padding(.bottom, 4).accessibilityLabel("読み込み中")
            } else if device?.state == "Shutdown", hub.listingReason == nil {
                RoundedRectangle(cornerRadius: 10).strokeBorder(DSColor.textTertiary, lineWidth: 1.5)
                    .frame(width: 44, height: 90).padding(.bottom, 6)
            } else {
                Image(systemName: "exclamationmark.circle").font(.system(size: 26))
                    .foregroundStyle(DSColor.textSecondary)
            }
            Text(title).font(DSFont.sessionTitle)
            Text(explanation).font(DSFont.auxiliary).foregroundStyle(DSColor.textSecondary).lineSpacing(4)
                .frame(maxWidth: 380)
                .help(hub.listingDiagnosticReason ?? explanation)
            if missingXcode { information("xcode-select -p") }
            if isUnverified {
                information("Xcode build \(connection?.capability?.xcodeBuild ?? "未取得")\n\(device?.runtimeLabel ?? "iOS 未取得")")
            }
            if incompatibleProtocol {
                information("通信仕様 \(connection?.capability?.protocolVersion ?? 0)（補助） · \(SimulatorBridgeInterfaces.protocolVersion)（本体）")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(spacing: 8) { actions }
            }.padding(.top, 6)
        }
        .multilineTextAlignment(.center).foregroundStyle(DSColor.textPrimary)
        .frame(maxWidth: 400).padding(.horizontal, 28).padding(.bottom, 30)
    }

    private func information(_ text: String) -> some View {
        Text(verbatim: text).font(DSFont.monoCaption).textSelection(.enabled)
            .foregroundStyle(DSColor.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(DSColor.codeBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
    }

    @ViewBuilder private var actions: some View {
        if hub.listingReason != nil {
            Button("再確認") { Task { await hub.refresh() } }
                .buttonStyle(.ds(.secondary, height: 24, fontSize: 12))
        } else if device?.state == "Shutdown" {
            Button("起動") { Task { await hub.boot(for: sessionID) } }
                .buttonStyle(.ds(.primary, height: 24, fontSize: 12))
        } else if connection?.reason != nil || isUnverified {
            if isUnverified {
                Button("未確認でも試す") { hub.tryUnverified(displayID: displayID) }
                    .buttonStyle(.ds(.secondary, height: 24, fontSize: 12))
                    .accessibilityIdentifier("simulator-try-unverified")
            }
            if connection?.canReconnect == true {
                Button("再接続") { connection?.reconnect() }
                    .buttonStyle(.ds(.secondary, height: 24, fontSize: 12))
                    .accessibilityIdentifier("simulator-reconnect")
            }
            Button("Simulator.app で開く", action: openSimulator)
                .buttonStyle(.ds(.secondary, height: 24, fontSize: 12))
                .accessibilityIdentifier("simulator-open-external")
        }
    }
}

struct SimulatorDiagnostics: View {
    var body: some View {
        Text("しばらく画面の更新を観測していません。画面が止まっているときは正常です。入力が届いているかの判断には使えません。")
            .font(DSFont.auxiliary).foregroundStyle(DSColor.textPrimary)
            .lineSpacing(4).padding(10).frame(width: 280)
    }
}

struct SimulatorShutdownDialog: View {
    let deviceName: String
    let displayCount: Int
    let shutdown: () -> Void
    let cancel: () -> Void

    var body: some View {
        DSDialog(.recoverable, title: "\(deviceName) を停止しますか？",
                 message: "この端末を表示中の他のタブ・Phlox の別の版・Simulator.app にも影響します。端末の中で動いているアプリは終了します。",
                 note: "停止したあとは、帯の「起動」で起動し直せます。",
                 buttons: [DSDialogButton("停止", role: .destructive, action: shutdown),
                           DSDialogButton("キャンセル", role: .primary, action: cancel)], onCancel: cancel) {
            Text("Phlox で表示中のタブ: この Phlox の \(displayCount) タブ")
                .font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).padding(.horizontal, 10)
                .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .overlay(RoundedRectangle(cornerRadius: DSRadius.row).strokeBorder(DSColor.controlBorder, lineWidth: 0.5))
        }
    }
}
