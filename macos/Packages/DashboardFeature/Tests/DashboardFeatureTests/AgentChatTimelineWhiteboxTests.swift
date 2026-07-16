import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private func whiteboxMsg(_ id: String, at t: TimeInterval?) -> TeamTimelineSourceMessage {
    TeamTimelineSourceMessage(
        id: id,
        timestamp: t.map { Date(timeIntervalSince1970: $0) },
        content: .terminalText(id)
    )
}

private func whiteboxSrc(
    _ id: SessionID,
    parent: SessionID?,
    name: String,
    _ messages: [TeamTimelineSourceMessage]
) -> AgentTimelineSource {
    AgentTimelineSource(
        id: id,
        parentSessionID: parent,
        displayName: name,
        agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
        messages: messages
    )
}

private func whiteboxShape(_ entries: [AgentTimelineEntry]) -> [String] {
    entries.map { entry in
        switch entry {
        case .message(let item):
            "m:\(item.sourceMessageID)"
        case .subsession(let subtree):
            "s:\(subtree.displayName)[\(whiteboxShape(subtree.entries).joined(separator: ","))]"
        }
    }
}

@Test func whitebox_timeline_anchorUsesUnprunedMessagesBeforeApplyingLimit() {
    let root = SessionID()
    let child = SessionID()

    let entries = AgentChatTimelineBuilder.build(
        sources: [
            whiteboxSrc(root, parent: nil, name: "main", [
                whiteboxMsg("a", at: 10),
                whiteboxMsg("b", at: 20),
                whiteboxMsg("c", at: 30),
                whiteboxMsg("d", at: 40),
            ]),
            whiteboxSrc(child, parent: root, name: "sub", [
                whiteboxMsg("old-anchor", at: 25),
                whiteboxMsg("visible", at: 35),
                whiteboxMsg("visible-2", at: 36),
                whiteboxMsg("visible-3", at: 37),
            ]),
        ],
        rootID: root,
        messageLimitPerSession: 3
    )

    #expect(whiteboxShape(entries) == ["m:b", "s:sub[m:visible,m:visible-2,m:visible-3]", "m:c", "m:d"])
}

@Test func whitebox_timeline_anchorUsesFirstTimestampInTranscriptOrderNotMinimumTimestamp() {
    let root = SessionID()
    let child = SessionID()

    let entries = AgentChatTimelineBuilder.build(
        sources: [
            whiteboxSrc(root, parent: nil, name: "main", [
                whiteboxMsg("a", at: 10),
                whiteboxMsg("b", at: 20),
                whiteboxMsg("c", at: 40),
            ]),
            whiteboxSrc(child, parent: root, name: "sub", [
                whiteboxMsg("first", at: 30),
                whiteboxMsg("minimum", at: 15),
            ]),
        ],
        rootID: root,
        messageLimitPerSession: 0
    )

    #expect(whiteboxShape(entries) == ["m:a", "m:b", "s:sub[m:first,m:minimum]", "m:c"])
}

@Test func whitebox_timeline_anchorUsesDescendantTimestampsWhenChildMessagesHaveNoTimestamp() {
    let root = SessionID()
    let child = SessionID()
    let grandchild = SessionID()

    let entries = AgentChatTimelineBuilder.build(
        sources: [
            whiteboxSrc(root, parent: nil, name: "main", [
                whiteboxMsg("a", at: 10),
                whiteboxMsg("b", at: 20),
            ]),
            whiteboxSrc(child, parent: root, name: "sub", [
                whiteboxMsg("child-nil", at: nil),
            ]),
            whiteboxSrc(grandchild, parent: child, name: "sub-child", [
                whiteboxMsg("grandchild-anchor", at: 15),
            ]),
        ],
        rootID: root,
        messageLimitPerSession: 0
    )

    #expect(whiteboxShape(entries) == ["m:a", "s:sub[s:sub-child[m:grandchild-anchor],m:child-nil]", "m:b"])
}

@Test func whitebox_timeline_nilParentTimestampsAreIgnoredForInsertionComparison() {
    let root = SessionID()
    let child = SessionID()

    let entries = AgentChatTimelineBuilder.build(
        sources: [
            whiteboxSrc(root, parent: nil, name: "main", [
                whiteboxMsg("nil-before", at: nil),
                whiteboxMsg("dated-before", at: 10),
                whiteboxMsg("nil-after", at: nil),
                whiteboxMsg("dated-after", at: 20),
            ]),
            whiteboxSrc(child, parent: root, name: "sub", [
                whiteboxMsg("x", at: 15),
            ]),
        ],
        rootID: root,
        messageLimitPerSession: 0
    )

    #expect(whiteboxShape(entries) == ["m:nil-before", "m:dated-before", "s:sub[m:x]", "m:nil-after", "m:dated-after"])
}

@Test func whitebox_timeline_cycleInParentReferencesTerminatesWithoutReEmbeddingVisitedSession() {
    let root = SessionID()
    let child = SessionID()

    let entries = AgentChatTimelineBuilder.build(
        sources: [
            whiteboxSrc(root, parent: child, name: "main", [
                whiteboxMsg("a", at: 10),
            ]),
            whiteboxSrc(child, parent: root, name: "sub", [
                whiteboxMsg("x", at: 15),
            ]),
        ],
        rootID: root,
        messageLimitPerSession: 0
    )

    #expect(whiteboxShape(entries) == ["m:a", "s:sub[m:x]"])
}

@Test func whitebox_timeline_sameAnchorSiblingsKeepSourceOrderStableForLargeInput() {
    let root = SessionID()
    let children = (0..<40).map { index in
        (id: SessionID(), name: String(format: "sub-%02d", index), messageID: String(format: "x%02d", index))
    }
    let sources = [
        whiteboxSrc(root, parent: nil, name: "main", [
            whiteboxMsg("a", at: 10),
            whiteboxMsg("b", at: 20),
        ]),
    ] + children.map { child in
        whiteboxSrc(child.id, parent: root, name: child.name, [
            whiteboxMsg(child.messageID, at: 15),
        ])
    }

    let first = AgentChatTimelineBuilder.build(
        sources: sources,
        rootID: root,
        messageLimitPerSession: 0
    )
    let second = AgentChatTimelineBuilder.build(
        sources: sources,
        rootID: root,
        messageLimitPerSession: 0
    )
    let expected = ["m:a"]
        + children.map { "s:\($0.name)[m:\($0.messageID)]" }
        + ["m:b"]

    #expect(whiteboxShape(first) == expected)
    #expect(whiteboxShape(second) == expected)
}

@Test func whitebox_timeline_buildsDeepChainWithinPerformanceBudget() {
    let root = SessionID()
    var sources = [
        whiteboxSrc(root, parent: nil, name: "main", [
            whiteboxMsg("root", at: 1),
        ]),
    ]
    var parent = root

    for index in 0..<2_000 {
        let child = SessionID()
        sources.append(
            whiteboxSrc(child, parent: parent, name: "sub-\(index)", [
                whiteboxMsg("m-\(index)", at: TimeInterval(index + 2)),
            ])
        )
        parent = child
    }

    let start = Date()
    let entries = AgentChatTimelineBuilder.build(
        sources: sources,
        rootID: root,
        messageLimitPerSession: 0
    )
    let elapsed = Date().timeIntervalSince(start)

    #expect(entries.count == 2)
    #expect(elapsed < 0.350)
}
