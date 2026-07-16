import AppKit
import SwiftUI
import SwiftTerm

@MainActor
public struct TerminalView: NSViewRepresentable {
    public let coordinator: TerminalCoordinator

    public init(coordinator: TerminalCoordinator) {
        self.coordinator = coordinator
    }

    public func makeNSView(context: Context) -> NSView {
        // SwiftUI が安全に所有・破棄できる軽量コンテナを毎回新規に作る。
        // 永続化された terminal 本体 (coordinator.hostingView) は updateNSView で
        // このコンテナへ reparent する。グリッドタイルと単体表示のように同じ
        // hostingView を複数のマウント先で共有しても、現在表示中のコンテナへ確実に
        // 張り替えられるため、モード切替後に片方が空白になる問題を防ぐ。
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // hostingView は coordinator が寿命を通じて1個だけ保持する。表示先の
        // コンテナが変わった（モード切替・セッション切替）ときだけ、現在のコンテナへ
        // 載せ替える。NSView は1つの superview にしか属せないため、まず旧 superview から
        // 外してから addSubview し、コンテナ全面に追従する制約を張り直す。
        let terminal = coordinator.hostingView
        // 単体表示はコンテナ (NSView) を再利用したまま coordinator だけ差し替えるため、
        // 直前に表示していた別セッションの terminal がコンテナに残っていると最前面に被さり、
        // セッション切替が反映されない。現在の terminal 以外は必ず取り除く。
        for sub in nsView.subviews where sub !== terminal {
            sub.removeFromSuperview()
        }
        guard terminal.superview !== nsView else { return }
        terminal.removeFromSuperview()
        nsView.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: nsView.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
        ])
    }
}

#if DEBUG
private struct TerminalViewPreviewContainer: View {
    @State private var coordinator = TerminalCoordinator()

    var body: some View {
        TerminalView(coordinator: coordinator)
            .frame(width: 480, height: 320)
            .onAppear {
                DispatchQueue.main.async {
                    coordinator.feed(Data("Hello from TerminalUI\n".utf8))
                }
            }
    }
}

#Preview {
    TerminalViewPreviewContainer()
}
#endif
