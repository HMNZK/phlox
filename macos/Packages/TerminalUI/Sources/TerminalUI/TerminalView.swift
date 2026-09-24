import AppKit
import SwiftUI
import SwiftTerm

/// SwiftUI の mount ごとに 1 個。struct 再評価では発行し直さず、現在の端末だけ差し替える。
@MainActor
public final class TerminalMountCoordinator {
    public var current: TerminalCoordinator
    public var hostingView: NSView { current.hostingView }
    private weak var container: TerminalMountContainer?
    private var releaseObserver: NSObjectProtocol?

    public init(current: TerminalCoordinator) {
        self.current = current
    }

    /// 所有していた mount が外れたら、まだ画面にある自分のコンテナへ付け直す。
    /// グリッドへの切り替えでは一時的な mount が最後に付いてすぐ破棄され、残ったタイルには
    /// updateNSView が来ないため、知らせないと端末がどこにも付かないまま空になる。
    /// 合図の時点で画面外だったコンテナは、画面に載った時点で付け直す。
    func observeRelease(for container: TerminalMountContainer) {
        self.container = container
        container.onMoveToWindow = { [weak self] in self?.scheduleReattach() }
        guard releaseObserver == nil else { return }
        releaseObserver = NotificationCenter.default.addObserver(
            forName: TerminalMount.didRelease, object: nil, queue: nil
        ) { [weak self] note in
            let released = note.object as? NSView
            MainActor.assumeIsolated {
                guard let self, released === self.hostingView else { return }
                self.scheduleReattach()
            }
        }
    }

    /// 次の runloop で、端末がまだどこにも付いていないときだけ付け直す。
    /// 合図を待つ間に別の mount が付けていたら奪わない。
    private func scheduleReattach() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let container = self.container, container.window != nil,
                      !TerminalMount.hasOwner(self.hostingView),
                      TerminalMount.attach(self.hostingView, to: container) else { return }
                self.current.scrollToBottom()
            }
        }
    }

    func stopObservingRelease() {
        if let releaseObserver { NotificationCenter.default.removeObserver(releaseObserver) }
        releaseObserver = nil
        container?.onMoveToWindow = nil
        container = nil
    }
}

/// 画面に載ったことを mount へ知らせる軽量コンテナ。
@MainActor
final class TerminalMountContainer: NSView {
    var onMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }
}

@MainActor
public struct TerminalView: NSViewRepresentable {
    public let coordinator: TerminalCoordinator

    public init(coordinator: TerminalCoordinator) {
        self.coordinator = coordinator
    }

    /// mount 寿命で同じ TerminalMountCoordinator を返す。struct 再評価のたびに所有者を新規発行しない。
    public func makeCoordinator() -> TerminalMountCoordinator {
        TerminalMountCoordinator(current: coordinator)
    }

    public func makeNSView(context: Context) -> NSView {
        // SwiftUI が安全に所有・破棄できる軽量コンテナを毎回新規に作る。
        // 永続化された terminal 本体 (coordinator.hostingView) は updateNSView で
        // このコンテナへ reparent する。グリッドタイルと単体表示のように同じ
        // hostingView を複数のマウント先で共有しても、最後に有効な接続を要求した
        // コンテナだけが所有し、旧 mount の後着 update では奪い返されない。
        let container = TerminalMountContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.observeRelease(for: container)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // hostingView は coordinator が寿命を通じて1個だけ保持する。
        // 最後に有効な接続を要求したコンテナだけが所有する。window == nil や
        // frame 0 では拒否しない（新しい単一コンテナも接続時点でこの状態になる）。
        context.coordinator.current = coordinator
        guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }
        // reparent 直後はコンテナのレイアウトが未確定なので、次の runloop で最下部へ戻す。
        // updateNSView 中に同期的なスクロール副作用を起こさない（ADR 0010）。
        DispatchQueue.main.async { [weak coordinator] in
            coordinator?.scrollToBottom()
        }
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: TerminalMountCoordinator) {
        coordinator.stopObservingRelease()
        _ = TerminalMount.detach(coordinator.hostingView, from: nsView)
    }
}

/// terminal を container へ載せ替える。所有権は最後に有効な接続を要求した
/// container に固定し、失効した旧 mount の後着 update では載せ替えない。
/// 実際に載せ替えたときだけ true を返すため、SwiftUI の Context に依存せず
/// 「開いたときだけ最下部へ寄せる」判定を検証できる。
@MainActor
enum TerminalMount {
    /// 所有していた container から外れた（object は terminal）。生きている mount が付け直す合図。
    static let didRelease = Notification.Name("TerminalMount.didRelease")

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

    static func hasOwner(_ terminal: NSView) -> Bool {
        records.object(forKey: terminal)?.owner != nil
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
            var released = false
            if let other = records.object(forKey: subview), other.owner === container {
                other.owner = nil
                other.formerOwners.removeAllObjects()
                released = true
            }
            subview.removeFromSuperview()
            if released { NotificationCenter.default.post(name: didRelease, object: subview) }
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
        NotificationCenter.default.post(name: didRelease, object: terminal)
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
