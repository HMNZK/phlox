import Foundation
import Testing
@testable import AgentDomain

private func whiteboxProject(isolation: Bool?) -> Project {
    Project(
        name: "whitebox",
        directoryPath: "/tmp/phlox-worktree-whitebox/repository",
        createdAt: Date(timeIntervalSince1970: 0),
        isManagedDirectory: false,
        worktreeIsolationEnabled: isolation
    )
}

@Test func planner_treatsOnlyExactBranchMatchAsCollision() {
    let sessionID = SessionID()
    let branch = WorktreeIsolationPlanner.branchName(for: sessionID)

    let outcome = WorktreeIsolationPlanner.plan(
        project: whiteboxProject(isolation: true),
        sessionID: sessionID,
        sessionWorkspaceDirectory: "/tmp/phlox-worktree-whitebox/session",
        isGitRepository: true,
        existingBranchNames: ["prefix-" + branch, branch + "-suffix"],
        worktreePathExists: false
    )

    #expect(outcome == .create(
        worktreePath: "/tmp/phlox-worktree-whitebox/session",
        branchName: branch
    ))
}

@Test func planner_branchName_passesGitRefFormatValidation() throws {
    let branch = WorktreeIsolationPlanner.branchName(for: SessionID())
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["check-ref-format", "refs/heads/" + branch]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
}
