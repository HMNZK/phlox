import SwiftUI
import WebKit
import DesignSystem

struct BrowserTabView: View {
    @Bindable var model: BrowserTabModel
    @State private var address = ""

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
