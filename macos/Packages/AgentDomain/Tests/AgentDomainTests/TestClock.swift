import Foundation

/// 受け入れテスト用の注入時計（PM が管理するテストハーネス）。
///
/// `@Sendable` クロージャは可変ローカル変数を捕捉できない（Swift 6）。
/// 一方で本番の注入口は `@Sendable` を要求する契約なので、テスト側は
/// 可変ローカルではなくロックで保護した参照型で時刻を進める。
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}
