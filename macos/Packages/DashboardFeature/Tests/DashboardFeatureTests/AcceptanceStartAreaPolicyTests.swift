import Testing
@testable import DashboardFeature

@Test func acceptance_startArea_selectedSessionShowsSessionContent() {
    #expect(StartAreaPolicy.content(hasSelectedSession: true) == .sessionContent)
}

@Test func acceptance_startArea_noSelectedSessionShowsNewChat() {
    #expect(StartAreaPolicy.content(hasSelectedSession: false) == .newChat)
}

@Test func acceptance_startArea_noProjectsShowsFolderRegistration() {
    #expect(StartAreaPolicy.content(hasSelectedSession: false, hasProjects: false) == .projectOnboarding)
    #expect(StartAreaPolicy.content(hasSelectedSession: true, hasProjects: false) == .projectOnboarding)
}
