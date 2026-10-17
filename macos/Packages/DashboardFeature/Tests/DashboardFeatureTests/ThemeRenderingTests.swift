import Testing

/// アプリ全体のテーマを切り替える検査は、非同期の描画が終わるまで同じテーマを保つ。
/// 個別スイートの serialized では、別スイートの切り替えを排他できない。
@Suite(.serialized)
struct ThemeRenderingTests {}

// 描画フィクスチャを使う、テーマを変更しないテストからの参照を保つ。
typealias DesignSnapshotRenderTests = ThemeRenderingTests.DesignSnapshotRenderTests
typealias GitWorkflowRenderTests = ThemeRenderingTests.GitWorkflowRenderTests
