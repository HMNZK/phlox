import AppKit
import SwiftUI
import SwiftTerm

@MainActor
public struct TerminalView: NSViewRepresentable {
    public let coordinator: TerminalCoordinator

    public init(coordinator: TerminalCoordinator) {
        self.coordinator = coordinator
    }

    /// mount 寿命で同じ Coordinator を返す。struct 再評価のたびに所有者を新規発行しない。
    public func makeCoordinator() -> TerminalCoordinator {
        coordinator
    }

    public func makeNSView(context: Context) -> NSView {
        // SwiftUI が安全に所有・破棄できる軽量コンテナを毎回新規に作る。
        // 永続化された terminal 本体 (coordinator.hostingView) は updateNSView で
        // このコンテナへ reparent する。グリッドタイルと単体表示のように同じ
        // hostingView を複数のマウント先で共有しても、最後に有効な接続を要求した
        // コンテナだけが所有し、旧 mount の後着 update では奪い返されない。
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // hostingView は coordinator が寿命を通じて1個だけ保持する。
        // 最後に有効な接続を要求したコンテナだけが所有する。window == nil や
        // frame 0 では拒否しない（新しい単一コンテナも接続時点でこの状態になる）。
        guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }
        // reparent 直後はコンテナのレイアウトが未確定なので、次の runloop で最下部へ戻す。
        // updateNSView 中に同期的なスクロール副作用を起こさない（ADR 0010）。
        DispatchQueue.main.async { [weak coordinator] in
            coordinator?.scrollToBottom()
        }
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: TerminalCoordinator) {
        _ = TerminalMount.detach(coordinator.hostingView, from: nsView)
    }
}

/// terminal を container へ載せ替える。所有権は最後に有効な接続を要求した
/// container に固定し、失効した旧 mount の後着 update では載せ替えない。
/// 実際に載せ替えたときだけ true を返すため、SwiftUI の Context に依存せず
/// 「開いたときだけ最下部へ寄せる」判定を検証できる。
@MainActor
enum TerminalMount {
    /// 端末ごとの所有権。キーは terminal（hostingView）の弱参照なので、
    /// 破棄済みビューをプロセス寿命で積み上げない。
    private static let records = NSMapTable<NSView, Record>.weakToStrongObjects()

    private final class Record: NSObject {
        weak var owner: NSView?
        let formerOwners = NSHashTable<NSView>.weakObjects()
    }

    private static func record(for terminal: NSView) -> Record {
        if let existing = records.object(forKey: terminal) {
            return existing
        }
        let created = Record()
        records.setObject(created, forKey: terminal)
        return created
    }

    static func attach(_ terminal: NSView, to container: NSView) -> Bool {
        let rec = record(for: terminal)
        if rec.owner == nil {
            rec.formerOwners.removeAllObjects()
        }
        // 所有権確認を subview の除去・追加・制約変更より先に行う。
        // 拒否する要求が別端末を container から除去してはならない。
        if rec.owner === container {
            return false
        }
        if rec.owner != nil && rec.formerOwners.contains(container) {
            return false
        }

        // 単体表示はコンテナを再利用したまま coordinator だけ差し替えるため、直前の terminal を解放する。
        for subview in container.subviews where subview !== terminal {
            if let other = records.object(forKey: subview), other.owner === container {
                other.owner = nil
                other.formerOwners.removeAllObjects()
            }
            subview.removeFromSuperview()
        }

        if let previous = rec.owner, previous !== container {
            rec.formerOwners.add(previous)
        }

        terminal.removeFromSuperview()
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        rec.owner = container
        return true
    }

    static func detach(_ terminal: NSView, from container: NSView) -> Bool {
        let rec = record(for: terminal)
        guard rec.owner === container else {
            return false
        }
        terminal.removeFromSuperview()
        rec.owner = nil
        rec.formerOwners.removeAllObjects()
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
