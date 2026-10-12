import Testing
@testable import DashboardFeature

@Suite("Acceptance: 新規チャットの見出し")
struct NewChatGreetingsAcceptanceTests {
    @Test("見出し候補は10種類で、選択結果は候補のいずれか")
    func selectsOneOfTenGreetings() {
        #expect(NewChatGreetings.all.count == 10)
        #expect(Set(NewChatGreetings.all).count == 10)
        #expect(NewChatGreetings.all.contains(NewChatGreetings.random()))
    }
}
