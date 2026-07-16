import Foundation
import PTYKit

/// 起動時 reconcile で「前回プロセスの生存孤児（クラッシュ/強制終了の生き残り）」を
/// 判定・reap するための小さな抽象。テストでモックを注入し、実プロセスに触れずに
/// reconcile ロジック（生存 pid→reap／死亡・nil→何もしない）を検証できるようにする。
///
/// 既定実装 `PosixOrphanReaper` は `Posix`（PTYKit）の public API を呼ぶ。
///
/// 不変条件: 呼び出し側は registry に記録された自分の pid 以外をこの抽象へ渡さない
/// （無関係プロセス・別アプリへはシグナルを送らない）。
///
/// スコープ前提: 二重起動（複数 Phlox 同時稼働）は未サポート＝スコープ外。pid 再利用の
/// 理論的リスク（記録 pid を OS が別プロセスに再割当）も既知制約として残し、本タスクでは
/// 対策しない。単一インスタンス前提では、記録 pid==自セッションの SETSID プロセスグループ。
public protocol OrphanReaper: Sendable {
    /// 指定 pid がまだプロセス表に存在するか。
    func isAlive(_ pid: pid_t) -> Bool
    /// 指定 pid を pgid とするプロセスグループ全体を reap（SIGKILL）する。
    func reap(_ pid: pid_t)
}

/// `Posix`（PTYKit）を呼ぶ既定実装。本番経路で使う。
public struct PosixOrphanReaper: OrphanReaper {
    public init() {}

    public func isAlive(_ pid: pid_t) -> Bool {
        Posix.isAlive(pid: pid)
    }

    public func reap(_ pid: pid_t) {
        // SETSID 起動の子は pgid == pid。プロセスグループへ SIGKILL を送って
        // master fd を失った再アタッチ不能の孤児を確実に掃除する。
        Posix.killGroup(pid: pid)
    }
}
