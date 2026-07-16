import Foundation
import AgentDomain

/// エージェントビューの入力欄の宛先解決（R3: 常にメインセッション＝ツリーの根へ送る）。
public enum TeamComposerTarget {
    /// 選択セッションが属するツリーの根セッション ID を返す。
    /// - `selectedSessionID` が nil、または `parentByID` に存在しないキーなら nil。
    /// - 親ポインタを根（parent が nil か、parentByID に無い ID）まで辿る。
    /// - 循環があっても無限ループしない（訪問済み検知で打ち切り、その時点の ID を返す）。
    public static func resolveRootSessionID(
        selectedSessionID: SessionID?,
        parentByID: [SessionID: SessionID?]
    ) -> SessionID? {
        guard let selectedSessionID, parentByID.keys.contains(selectedSessionID) else {
            return nil
        }

        var current = selectedSessionID
        var visited: Set<SessionID> = []

        while true {
            guard visited.insert(current).inserted else {
                return current
            }
            guard let parent = parentByID[current] else {
                return current
            }
            guard let parent, parentByID.keys.contains(parent) else {
                return current
            }
            current = parent
        }
    }
}
