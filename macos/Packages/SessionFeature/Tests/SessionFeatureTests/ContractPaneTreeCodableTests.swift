import Foundation
import Testing
import AgentDomain
@testable import SessionFeature

// シーム契約テスト: PaneTree の Codable 表現。
// PaneTree（SessionFeature / task-1）と PaneLayoutStore（DashboardFeature / task-3）が
// 共有する永続化の境界。task-1・task-3・task-5 の verify とマージ時に再実走する。
// PM が著す不変の契約（実装役は編集禁止。ハーネスの欠陥は PM に報告して承認を得てから修理）。
//
// 契約の骨子:
// - エンコード結果のトップレベルはオブジェクトで `schemaVersion` キーを持つ。
// - 往復で木が完全に一致する（PaneID・weights・構造・セッション）。
// - 壊れたデータ・未知バージョン・不変条件違反は throw する（黙って通さない）。

// MARK: - ハーネス

private func sid(_ n: Int) -> SessionID {
    let hex = String(format: "%012x", n)
    return SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(hex)")!)
}

private func pid(_ name: String) -> PaneID { PaneID(name) }

private func leaf(_ name: String, _ session: SessionID) -> PaneNode {
    .leaf(id: pid(name), session: session)
}

private func split(
    _ name: String,
    _ axis: PaneAxis,
    _ children: [PaneNode],
    _ weights: [Double]
) -> PaneNode {
    .split(PaneSplit(id: pid(name), axis: axis, children: children, weights: weights))
}

private func encode(_ tree: PaneTree) throws -> Data {
    try JSONEncoder().encode(tree)
}

private func decode(_ data: Data) throws -> PaneTree {
    try JSONDecoder().decode(PaneTree.self, from: data)
}

/// 一度エンコードしたうえでトップレベルの1キーを差し替える（表現の細部に依存しない改竄）。
private struct TopLevelIsNotAnObject: Error {}

private func mutatingTopLevel(_ tree: PaneTree, _ transform: (inout [String: Any]) -> Void) throws -> Data {
    let data = try encode(tree)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TopLevelIsNotAnObject()   // 契約違反（トップレベルはオブジェクトであること）
    }
    transform(&object)
    return try JSONSerialization.data(withJSONObject: object)
}

private func sampleTree() throws -> PaneTree {
    try PaneTree(root: split(
        "root", .horizontal,
        [
            leaf("A", sid(1)),
            split("R", .vertical, [leaf("B", sid(2)), leaf("C", sid(3))], [0.3, 0.7]),
        ],
        [0.62, 0.38]
    ))
}

// MARK: - 往復

@Test
func codable_roundTripsEmptyTree() throws {
    let tree = try PaneTree(root: nil)
    #expect(try decode(try encode(tree)) == tree)
}

@Test
func codable_roundTripsSingleLeaf() throws {
    let tree = try PaneTree(root: leaf("only", sid(1)))
    #expect(try decode(try encode(tree)) == tree)
}

@Test
func codable_roundTripsNestedTreeWithUnevenWeights() throws {
    let tree = try sampleTree()
    #expect(try decode(try encode(tree)) == tree)
}

@Test
func codable_roundTripsManyChildren() throws {
    let ids = (1...30).map(sid)
    let tree = try PaneTree(root: split(
        "S", .vertical,
        ids.enumerated().map { leaf("L\($0.offset)", $0.element) },
        (1...30).map { Double($0) }
    ))
    #expect(try decode(try encode(tree)) == tree)
}

@Test
func codable_preservesPaneIDsSoDividerIdentityIsStable() throws {
    let tree = try sampleTree()
    let restored = try decode(try encode(tree))

    let bounds = CGSize(width: 1200, height: 900)
    let before = tree.frames(in: bounds, spacing: 8).dividers.map(\.id)
    let after = restored.frames(in: bounds, spacing: 8).dividers.map(\.id)
    #expect(before == after, "往復後も分割線 ID が同一（D10 の前提）")
    #expect(!before.isEmpty)
}

@Test
func codable_preservesSessionOrder() throws {
    let tree = try sampleTree()
    #expect(try decode(try encode(tree)).sessions == tree.sessions)
}

// MARK: - schemaVersion

@Test
func codable_encodesSchemaVersion() throws {
    let data = try encode(try sampleTree())
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let version = try #require(object["schemaVersion"] as? Int, "schemaVersion が Int で載っていること")
    #expect(version == PaneTree.schemaVersion)
    #expect(version == 1)
}

@Test
func codable_rejectsUnknownSchemaVersion() throws {
    let data = try mutatingTopLevel(try sampleTree()) { $0["schemaVersion"] = 999 }
    #expect(throws: (any Error).self) { _ = try decode(data) }
}

@Test
func codable_rejectsMissingSchemaVersion() throws {
    let data = try mutatingTopLevel(try sampleTree()) { $0.removeValue(forKey: "schemaVersion") }
    #expect(throws: (any Error).self) { _ = try decode(data) }
}

// MARK: - 壊れたデータ

@Test
func codable_rejectsGarbageBytes() {
    #expect(throws: (any Error).self) {
        _ = try decode(Data([0x00, 0x01, 0x02, 0xff, 0xfe]))
    }
}

@Test
func codable_rejectsEmptyData() {
    #expect(throws: (any Error).self) { _ = try decode(Data()) }
}

@Test
func codable_rejectsTruncatedJSON() throws {
    let data = try encode(try sampleTree())
    let truncated = data.prefix(data.count / 2)
    #expect(throws: (any Error).self) { _ = try decode(Data(truncated)) }
}

@Test
func codable_rejectsUnrelatedJSON() throws {
    let data = try #require(#"{"hello":"world"}"#.data(using: .utf8))
    #expect(throws: (any Error).self) { _ = try decode(data) }
}

// MARK: - 不変条件違反のデータを黙って通さない

@Test
func codable_rejectsDuplicateSessionInPayload() throws {
    // C のセッション UUID を A のものに書き換える（表現の細部に依存しない文字列置換）。
    let tree = try sampleTree()
    let data = try encode(tree)
    let json = try #require(String(data: data, encoding: .utf8))
    let tampered = json.replacingOccurrences(
        of: sid(3).rawValue.uuidString,
        with: sid(1).rawValue.uuidString
    )
    #expect(tampered != json, "置換が実際に起きていること（ハーネスの自己検査）")
    let tamperedData = try #require(tampered.data(using: .utf8))
    #expect(throws: (any Error).self) { _ = try decode(tamperedData) }
}

@Test
func codable_rejectsDuplicatePaneIDInPayload() throws {
    // R（split の PaneID）を A（leaf の PaneID）に書き換えて重複させる。
    let tree = try sampleTree()
    let data = try encode(tree)
    let json = try #require(String(data: data, encoding: .utf8))
    let tampered = json.replacingOccurrences(of: "\"R\"", with: "\"A\"")
    #expect(tampered != json, "置換が実際に起きていること（ハーネスの自己検査）")
    let tamperedData = try #require(tampered.data(using: .utf8))
    #expect(throws: (any Error).self) { _ = try decode(tamperedData) }
}
