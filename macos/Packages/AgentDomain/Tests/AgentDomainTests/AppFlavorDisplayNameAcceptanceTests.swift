// task-10 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-10.md — Debug ビルドの表示名に "(Debug)" を含める。

import Testing
@testable import AgentDomain

@Test func appFlavorDisplayName_releaseIsPhlox() {
    #expect(AppFlavor.release.displayName == "Phlox")
}

@Test func appFlavorDisplayName_debugHasDebugSuffix() {
    #expect(AppFlavor.debug.displayName == "Phlox (Debug)")
}
