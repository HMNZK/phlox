import XCTest
@testable import Features

@MainActor
final class EmptyStateViewTests: XCTestCase {
    func testCopyMatchesListEmptyDesign() {
        XCTAssertEqual(EmptyStateCopy.title, "セッションがありません")
        XCTAssertEqual(
            EmptyStateCopy.subtitle,
            "Mac でエージェントを動かすと、ここにセッションが並びます。iPhone から始めるときは「新規チャット」を押してください。"
        )
        XCTAssertEqual(
            EmptyStateCopy.projectNote,
            "プロジェクトの欄は、セッションが 1 つ以上あるプロジェクトだけが出ます。"
        )
        XCTAssertEqual(EmptyStateCopy.ctaTitle, "新規チャット")
    }
}
