import Foundation
import Testing
@testable import CodexAppServerKit

@Suite("Whitebox: item/tool/requestUserInput の型デコード")
struct RequestUserInputWhiteboxTests {
    @Test("質問のフラグは JSON で省略されたとき false になる")
    func questionFlagsDefaultToFalse() throws {
        let question = try JSONDecoder.appServer.decode(
            ToolRequestUserInputQuestion.self,
            from: Data(#"{"id":"q1","header":"h","question":"q"}"#.utf8)
        )

        #expect(question.isOther == false)
        #expect(question.isSecret == false)
    }
}
