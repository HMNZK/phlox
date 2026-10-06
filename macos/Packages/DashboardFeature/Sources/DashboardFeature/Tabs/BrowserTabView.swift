import SwiftUI
import WebKit
import DesignSystem

struct BrowserTabView: View {
    @Bindable var model: BrowserTabModel
    /// 表示中のページをこのセッションの入力欄に入れる（FR-11）。
    var tellAgent: ((String) -> Void)? = nil
    @State private var address = ""
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                toolbar(showsTitle: geometry.size.width >= 480)
                    .frame(height: 30)
            }
            .padding(.horizontal, DSSpacing.xs)
            .frame(height: 30)
            .background(DSColor.panelBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
            if model.showsFind { findBar }
            ZStack {
                BrowserWebView(model: model)
                if let error = model.error {
                    VStack(spacing: DSSpacing.s) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundStyle(DSColor.textTertiary)
                        Text("ページを開けません").font(DSFont.row.weight(.semibold))
                        Text(LocalizedStringKey(error)).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("再読込") { model.reloadOrStop() }
                            .buttonStyle(.ds(.secondary, height: 24, fontSize: 11))
                            .disabled(model.url == nil)
                    }
                    .padding(DSSpacing.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.background)
                } else if model.url == nil {
                    VStack(spacing: DSSpacing.s) {
                        Image(systemName: "globe").font(.system(size: 24)).foregroundStyle(DSColor.textTertiary)
                        Text("URL またはファイルのパスを入力").font(DSFont.row.weight(.semibold))
                        Text("Web ページとローカル HTML を開けます").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DSColor.background)
                }
            }
        }
        .foregroundStyle(DSColor.textPrimary)
        .onAppear { address = model.url?.absoluteString ?? "" }
        .onChange(of: model.url) { _, url in address = url?.absoluteString ?? "" }
        // 閉じるときは入力先を消さない（closeFind がページへ戻す）。
        .onChange(of: model.findFocusRequest) { findFocused = true }
        .onAppear { if model.showsFind { findFocused = true } }
    }

    private var findBar: some View {
        HStack(spacing: DSSpacing.xxs) {
            TextField("ページ内を検索", text: $model.findText)
                .textFieldStyle(.plain)
                .font(DSFont.meta)
                .padding(.horizontal, DSSpacing.xs)
                .frame(maxWidth: 240)
                .frame(height: 22)
                .background(DSColor.windowBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .focused($findFocused)
                .onChange(of: model.findText) { model.find() }
                .onKeyPress(.return, phases: .down) { press in
                    // 日本語入力の変換を確定する Enter は入力欄に渡す。
                    if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return .ignored }
                    model.find(backwards: press.modifiers.contains(.shift))
                    return .handled
                }
                .onExitCommand { model.closeFind() }
                .accessibilityLabel("ページ内を検索")
                .accessibilityIdentifier("browser-find")
            if model.findNotFound {
                Text("見つかりません").font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
            }
            icon("chevron.left", "前を検索", enabled: !model.findText.isEmpty) { model.find(backwards: true) }
            icon("chevron.right", "次を検索", enabled: !model.findText.isEmpty) { model.find() }
            Spacer(minLength: 0)
            Button("完了") { model.closeFind() }
                .buttonStyle(.ds(.secondary, height: 20, fontSize: 11))
        }
        .padding(.horizontal, DSSpacing.xs)
        .frame(height: 30)
        .background(DSColor.panelBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(DSColor.separator).frame(height: 1) }
    }

    private func toolbar(showsTitle: Bool) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            icon("chevron.left", "戻る", enabled: model.canGoBack, action: model.back)
            icon("chevron.right", "進む", enabled: model.canGoForward, action: model.forward)
            icon(model.isLoading ? "xmark" : "arrow.clockwise", model.isLoading ? "中止" : "再読込",
                 enabled: model.url != nil, action: model.reloadOrStop)
            TextField("URL またはファイルの絶対パス", text: $address)
                .textFieldStyle(.plain)
                .font(DSFont.meta)
                .padding(.horizontal, DSSpacing.xs)
                .frame(minWidth: 120, idealWidth: 200, maxWidth: .infinity)
                .frame(height: 22)
                .background(DSColor.windowBackground, in: RoundedRectangle(cornerRadius: DSRadius.row))
                .onSubmit { model.submit(address) }
                .accessibilityLabel("URL またはファイルの絶対パス")
                .accessibilityIdentifier("browser-address")
            if model.isLoading {
                ProgressView().controlSize(.mini).frame(width: 16)
                    .accessibilityLabel("読み込み中")
            }
            if model.pageZoom != 1 {
                Button { model.zoom(by: nil) } label: {
                    Text(verbatim: "\(Int((model.pageZoom * 100).rounded()))%").font(DSFont.meta).padding(.horizontal, 4)
                        .frame(height: 20)
                }
                .buttonStyle(HoverableSurfaceButtonStyle(cornerRadius: 5, baseFill: DSColor.fillSelected, hoverFill: DSColor.fillSelected))
                .help("倍率を元に戻す")
                .accessibilityLabel("倍率を元に戻す")
                .accessibilityIdentifier("browser-zoom")
            }
            icon("magnifyingglass", "ページ内検索", enabled: model.url != nil) { model.showFind() }
            icon("arrow.up.forward.app", "既定のブラウザで開く", enabled: model.url != nil, action: model.openInDefaultBrowser)
            icon("text.bubble", "エージェントに伝える", enabled: model.url != nil && tellAgent != nil) {
                if let hint = model.agentHint { tellAgent?(hint) }
            }
            if showsTitle, !model.title.isEmpty {
                Text(verbatim: model.title).font(DSFont.meta).foregroundStyle(DSColor.textSecondary)
                    .lineLimit(1).frame(minWidth: 100, maxWidth: 160, alignment: .trailing)
                    .help(model.title)
            }
        }
    }

    private func icon(_ name: String, _ label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(DSFont.meta).frame(width: 24, height: 24)
        }
        .buttonStyle(HoverableIconButtonStyle())
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let model: BrowserTabModel
    func makeNSView(context: Context) -> WKWebView { model.makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
