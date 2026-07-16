import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// MARK: - SpawnPolicy privileged requester (MC-2b)

/// MC-2b: モバイルトークンの安定 requester に「全 remove 無条件許可」の特権を付与する。
/// これらは純粋関数 `SpawnPolicy.isAuthorizedToRemove` の特権引数を直接検証する
/// （ViewModel 配線とは独立に、認可の核を担保する）。

@Test
func privilegedRequester_authorizesRemovalOfRootNonDescendantAndUnknown() {
    let mobile = SessionID()      // 特権 requester（どの木にも属さない固定 ID）
    let root = SessionID()
    let child = SessionID()
    let unrelated = SessionID()   // 別の root
    let missing = SessionID()     // parents に存在しない

    let parents: [SessionID: SessionID?] = [
        root: SessionID?.none,
        child: root,
        unrelated: SessionID?.none,
    ]

    // 既定（特権なし）: 非子孫の任意 ID は root や child の削除を許可されない。
    #expect(!SpawnPolicy.isAuthorizedToRemove(root, requester: mobile, parents: parents))
    #expect(!SpawnPolicy.isAuthorizedToRemove(child, requester: mobile, parents: parents))
    #expect(!SpawnPolicy.isAuthorizedToRemove(unrelated, requester: mobile, parents: parents))

    // 特権設定時: root・非子孫の任意セッション・unknown のいずれも remove 許可になる。
    #expect(SpawnPolicy.isAuthorizedToRemove(root, requester: mobile, parents: parents, privilegedRequester: mobile))
    #expect(SpawnPolicy.isAuthorizedToRemove(child, requester: mobile, parents: parents, privilegedRequester: mobile))
    #expect(SpawnPolicy.isAuthorizedToRemove(unrelated, requester: mobile, parents: parents, privilegedRequester: mobile))
    #expect(SpawnPolicy.isAuthorizedToRemove(missing, requester: mobile, parents: parents, privilegedRequester: mobile))
}

@Test
func privilegedRequester_defaultNilLeavesAncestorBehaviorUnchanged() {
    let root = SessionID()
    let child = SessionID()
    let grandchild = SessionID()
    let sibling = SessionID()
    let parents: [SessionID: SessionID?] = [
        root: SessionID?.none,
        child: root,
        grandchild: child,
        sibling: SessionID?.none,
    ]

    // 明示 nil（= 既定）でも、特権引数を付けない呼び出しと完全に同じ判定であること。
    #expect(SpawnPolicy.isAuthorizedToRemove(child, requester: root, parents: parents, privilegedRequester: nil)
        == SpawnPolicy.isAuthorizedToRemove(child, requester: root, parents: parents))
    #expect(SpawnPolicy.isAuthorizedToRemove(grandchild, requester: root, parents: parents, privilegedRequester: nil)
        == SpawnPolicy.isAuthorizedToRemove(grandchild, requester: root, parents: parents))
    #expect(SpawnPolicy.isAuthorizedToRemove(grandchild, requester: sibling, parents: parents, privilegedRequester: nil)
        == SpawnPolicy.isAuthorizedToRemove(grandchild, requester: sibling, parents: parents))

    // ancestor ベースの本来挙動: sibling は grandchild を削除できない。
    #expect(!SpawnPolicy.isAuthorizedToRemove(grandchild, requester: sibling, parents: parents, privilegedRequester: nil))
    // root は子孫 grandchild を削除できる。
    #expect(SpawnPolicy.isAuthorizedToRemove(grandchild, requester: root, parents: parents, privilegedRequester: nil))
}

@Test
func privilegedRequester_doesNotElevateNonPrivilegedRequesters() {
    let mobile = SessionID()
    let sibling = SessionID()
    let root = SessionID()
    let grandchild = SessionID()
    let child = SessionID()
    let parents: [SessionID: SessionID?] = [
        root: SessionID?.none,
        child: root,
        grandchild: child,
        sibling: SessionID?.none,
    ]

    // 特権を設定しても、その特権 ID と一致しない sibling は従来どおり ancestor 範囲のみ。
    #expect(!SpawnPolicy.isAuthorizedToRemove(grandchild, requester: sibling, parents: parents, privilegedRequester: mobile))
    #expect(!SpawnPolicy.isAuthorizedToRemove(root, requester: sibling, parents: parents, privilegedRequester: mobile))
    // root は依然として子孫 grandchild を削除できる（緩めも締めもしない）。
    #expect(SpawnPolicy.isAuthorizedToRemove(grandchild, requester: root, parents: parents, privilegedRequester: mobile))
}

@Test
func privilegedRequester_nilNeverGrantsBlanketAuthority() {
    // privilegedRequester=nil のとき、requester=nil の対象不明等を除き
    // 非子孫 requester に全権を与えてはならない（誤って nil==nil 一致で許可しないこと）。
    let sibling = SessionID()
    let root = SessionID()
    let child = SessionID()
    let parents: [SessionID: SessionID?] = [
        root: SessionID?.none,
        child: root,
    ]

    #expect(!SpawnPolicy.isAuthorizedToRemove(child, requester: sibling, parents: parents, privilegedRequester: nil))
}
