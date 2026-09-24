import Testing
import CodexAppServerKit
@testable import SessionFeature

// 権限の変更の承認（05 R6f）: Codex の RequestPermissionProfile を「種類 → 対象」の行にする。
// 形は `codex app-server generate-json-schema`（0.156.1）の PermissionsRequestApprovalParams。

@Test func permissionRows_networkAndLegacyPathsAndEntries() {
    let profile: JSONValue = .object([
        "network": .object(["enabled": .bool(true)]),
        "fileSystem": .object([
            "write": .array([.string("/Users/me/dev/phlox/build")]),
            "entries": .array([
                .object(["access": .string("read"), "path": .object(["type": .string("path"), "path": .string("/etc/hosts")])]),
                .object(["access": .string("write"), "path": .object(["type": .string("glob_pattern"), "pattern": .string("**/*.log")])]),
                .object(["access": .string("deny"), "path": .object([
                    "type": .string("special"),
                    "value": .object(["kind": .string("project_roots"), "subpath": .string(".git")]),
                ])]),
            ]),
        ]),
    ])

    let rows = ChatApprovalBroker.permissionRows(profile)

    #expect(rows == [
        ApprovalPermissionRow(label: "ネットワーク", value: "外部への接続", isPath: false),
        ApprovalPermissionRow(label: "読み取り", value: "/etc/hosts", isPath: true),
        ApprovalPermissionRow(label: "書き込み", value: "/Users/me/dev/phlox/build\n**/*.log", isPath: true),
        ApprovalPermissionRow(label: "拒否", value: "<project>/.git", isPath: true),
    ])
}

@Test func permissionRows_emptyForUnknownShape() {
    #expect(ChatApprovalBroker.permissionRows(.object(["allow": .array([.string("Bash(git push:*)")])])).isEmpty)
    #expect(ChatApprovalBroker.permissionRows(.string("x")).isEmpty)
    #expect(ChatApprovalBroker.permissionRows(.object(["network": .object(["enabled": .bool(false)])])).isEmpty)
}
