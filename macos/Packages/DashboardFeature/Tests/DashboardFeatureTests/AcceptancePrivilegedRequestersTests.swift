import AgentDomain
import Foundation
import Testing

@testable import DashboardFeature

// task-3 の受け入れテスト（PM が凍結・実装役は編集不可）。
//
// 固定する契約: 特権 requester を集合へ拡張しても、
//  (a) 空集合のときは現行の nil と完全に同じ（ancestor ベース）
//  (b) 集合に含まれる requester は全 remove を無条件に許可される
//  (c) 集合に含まれない requester は昇格しない（＝認可の緩みを作らない）
//  (d) 1 台を失効させても他端末の特権が落ちない
//
// (c) が最重要。ここが緩むとセキュリティ後退になる。

struct AcceptancePrivilegedRequestersTests {
    @Test
    func emptySet_behavesExactlyLikeLegacyNil() {
        let root = SessionID()
        let child = SessionID()
        let grandchild = SessionID()
        let sibling = SessionID()
        let parents: [SessionID: SessionID?] = [
            root: nil,
            child: root,
            grandchild: child,
            sibling: root,
        ]

        // 祖先は許可される。
        #expect(SpawnPolicy.isAuthorizedToRemove(grandchild, requester: root, parents: parents, privilegedRequesters: []))
        #expect(SpawnPolicy.isAuthorizedToRemove(child, requester: root, parents: parents, privilegedRequesters: []))
        // 祖先でない兄弟は許可されない。
        #expect(!SpawnPolicy.isAuthorizedToRemove(grandchild, requester: sibling, parents: parents, privilegedRequesters: []))
        // 自己 kill と requester なしは許可される。
        #expect(SpawnPolicy.isAuthorizedToRemove(child, requester: child, parents: parents, privilegedRequesters: []))
        #expect(SpawnPolicy.isAuthorizedToRemove(child, requester: nil, parents: parents, privilegedRequesters: []))
    }

    @Test
    func everyPrivilegedRequester_isAuthorizedForAnyTarget() {
        let phone = SessionID()
        let pad = SessionID()
        let root = SessionID()
        let child = SessionID()
        let unknown = SessionID()
        let parents: [SessionID: SessionID?] = [root: nil, child: root]
        let privileged: Set<SessionID> = [phone, pad]

        for requester in [phone, pad] {
            #expect(SpawnPolicy.isAuthorizedToRemove(root, requester: requester, parents: parents, privilegedRequesters: privileged))
            #expect(SpawnPolicy.isAuthorizedToRemove(child, requester: requester, parents: parents, privilegedRequesters: privileged))
            #expect(SpawnPolicy.isAuthorizedToRemove(unknown, requester: requester, parents: parents, privilegedRequesters: privileged))
        }
    }

    @Test
    func nonPrivilegedRequester_isNotElevated() {
        let phone = SessionID()
        let outsider = SessionID()
        let root = SessionID()
        let child = SessionID()
        let grandchild = SessionID()
        let parents: [SessionID: SessionID?] = [root: nil, child: root, grandchild: child]
        let privileged: Set<SessionID> = [phone]

        // 特権集合に居ない requester は、祖先でない対象を remove できない。
        #expect(!SpawnPolicy.isAuthorizedToRemove(grandchild, requester: outsider, parents: parents, privilegedRequesters: privileged))
        #expect(!SpawnPolicy.isAuthorizedToRemove(root, requester: outsider, parents: parents, privilegedRequesters: privileged))
        // 祖先であれば従来どおり許可される（特権集合の有無で ancestor 判定が変わらない）。
        #expect(SpawnPolicy.isAuthorizedToRemove(grandchild, requester: root, parents: parents, privilegedRequesters: privileged))
    }

    @Test
    func revokingOneDevice_doesNotDropOtherDevicesPrivilege() {
        let phone = SessionID()
        let pad = SessionID()
        let root = SessionID()
        let parents: [SessionID: SessionID?] = [root: nil]

        // phone を失効させた後の集合。
        let afterRevoke: Set<SessionID> = [pad]

        #expect(SpawnPolicy.isAuthorizedToRemove(root, requester: pad, parents: parents, privilegedRequesters: afterRevoke))
        #expect(!SpawnPolicy.isAuthorizedToRemove(root, requester: phone, parents: parents, privilegedRequesters: afterRevoke))
    }

    @Test
    func result_doesNotDependOnSetIterationOrder() {
        // Set の反復順は不定。同じ内容の集合を別の順序で作っても結果が一致すること。
        let phone = SessionID()
        let pad = SessionID()
        let mac = SessionID()
        let target = SessionID()
        let parents: [SessionID: SessionID?] = [target: nil]

        let a: Set<SessionID> = [phone, pad, mac]
        let b: Set<SessionID> = [mac, pad, phone]

        #expect(
            SpawnPolicy.isAuthorizedToRemove(target, requester: pad, parents: parents, privilegedRequesters: a)
                == SpawnPolicy.isAuthorizedToRemove(target, requester: pad, parents: parents, privilegedRequesters: b)
        )
    }
}
