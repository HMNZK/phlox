import CoreGraphics

// タイルへドロップしたときに「入れ替え」か「分割して差し込む」かを決める純粋な判定。
// UI 非依存（CoreGraphics のみ）。ビュー側に閾値を書かせないための唯一の関所であり、
// 表示するインジケータも実際に起きる操作も、この1つの関数の戻り値から導く
// （見た目と結果がずれる余地を作らない）。

/// タイルへのドロップが表す操作。
public enum PaneDropTarget: Equatable, Sendable {
    /// 中央へのドロップ = 入れ替え。
    case swap
    /// 端へのドロップ = その方向へ分割して差し込む。
    case split(PaneEdge)
}

public enum PaneDropZone {
    /// 端と判定する帯の割合（各軸のサイズに対する比）。0.25 なので中央は常に 50%×50% 残る。
    public static let edgeFraction: CGFloat = 0.25

    /// タイル内のローカル座標から操作の種類を決める。
    ///
    /// 4辺への距離は **絶対値（points）ではなく各軸のサイズに対する比**で測る。絶対値で測ると、
    /// 横長のタイルでは上下の帯だけが分厚く見え（短辺側の帯が中央を食い尽くし）、細いタイルでは
    /// 左右の帯が中央を潰す。比で測れば縦横比によらず中央 50%×50% が必ず残る。
    ///
    /// 距離そのものは **符号を落として（絶対値で）** 測る。符号つきの比のままだと、タイルの外側の点で
    /// 「はみ出しが大きい辺ほど小さい（負に大きい）値」になり、**最も遠い辺**が選ばれる。
    /// 例: `size = (400, 200)` の `(-10, -100)` は左へ 10pt・上へ 100pt はみ出しているので近いのは左辺だが、
    /// 符号つきでは top(-0.5) < leading(-0.025) となり上辺が選ばれてしまう。
    ///
    /// - 最小の比が `edgeFraction` **未満**なら、その辺への `split`（ちょうど `edgeFraction` は中央側）。
    /// - **タイルの外へ出た点は、比の大小に関わらず最も近い辺への `split`**。外にいる点は定義上「中央」では
    ///   ないので、帯の太さで入れ替えへ倒すと「境界の外へ出したのに入れ替わる」ことになる。
    /// - 同率のときは leading → top → trailing → bottom の順で決める（決定論）。
    /// - `size` の幅か高さが 0 以下なら `.swap`（退化ケースで分割を誘発しない）。
    public static func target(for point: CGPoint, in size: CGSize) -> PaneDropTarget {
        guard size.width > 0, size.height > 0 else { return .swap }

        // 並び順がそのまま同率時の優先順位になる。
        let ratios: [(edge: PaneEdge, ratio: CGFloat)] = [
            (.leading, abs(point.x) / size.width),
            (.top, abs(point.y) / size.height),
            (.trailing, abs(size.width - point.x) / size.width),
            (.bottom, abs(size.height - point.y) / size.height),
        ]

        // `<`（同率では入れ替えない）で走査するので、同率は必ず先頭側の辺が残る。
        // NaN が混ざっても比較が全て false になるだけで、先頭の候補が残り `.swap` へ倒れる。
        var nearest = ratios[0]
        for candidate in ratios.dropFirst() where candidate.ratio < nearest.ratio {
            nearest = candidate
        }

        let isOutside = point.x < 0 || point.y < 0 || point.x > size.width || point.y > size.height
        return isOutside || nearest.ratio < edgeFraction ? .split(nearest.edge) : .swap
    }
}
