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
        guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }
        // reparent 直後はコンテナのレイアウトが未確定なので、次の runloop で最下部へ戻す。
        // updateNSView 中に同期的なスクロール副作用を起こさない（ADR 0010）。
        DispatchQueue.main.async { [weak coordinator] in
            coordinator?.scrollToBottom()
        }
    }
}

/// terminal を container へ載せ替える。実際に載せ替えたときだけ true を返すため、
/// SwiftUI の Context に依存せず「開いたときだけ最下部へ寄せる」判定を検証できる。
@MainActor
enum TerminalMount {
    static func attach(_ terminal: NSView, to container: NSView) -> Bool {
        // 単体表示はコンテナを再利用したまま coordinator だけ差し替えるため、直前の terminal を除去する。
        for subview in container.subviews where subview !== terminal {
            subview.removeFromSuperview()
        }
        guard terminal.superview !== container else { return false }

        terminal.removeFromSuperview()
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return true
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
