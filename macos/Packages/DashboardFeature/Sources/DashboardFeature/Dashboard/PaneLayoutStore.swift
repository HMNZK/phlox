import CoreGraphics
import Foundation
import SessionFeature

/// `PaneTree`（分割ツリー）の永続化層。
/// 保存失敗時も throw せず、壊れたデータは nil を返して既定へフォールバックさせる。
public struct PaneLayoutStore {
    public static let stateStorageKey = "phlox.grid.layoutState"
    public static let storageKey = "phlox.grid.paneLayout"
    /// 最後に選んだプリセットと、そのあと手で崩したか（表示範囲バーの「レイアウト: 名前（調整済み）」）。
    public static let presetStorageKey = "phlox.grid.paneLayoutPreset"

    public struct PresetState: Codable, Equatable, Sendable {
        public var preset: PaneLayoutPreset
        public var isAdjusted: Bool

        public init(preset: PaneLayoutPreset = .balanced, isAdjusted: Bool = false) {
            self.preset = preset
            self.isAdjusted = isAdjusted
        }
    }

    /// `insertingIntoLargestPane` が「面積が最大のペイン」を決めるための固定の基準サイズ。
    /// VM は実際のウィンドウサイズを知らないため、reconcile 時はこの固定値を使う。
    /// これは「どのペインが大きいか」の相対比較にしか使わないので、実描画サイズと違っても
    /// 選ばれるペインは同じになる（アスペクト比が極端に違う場合のみ差が出るが許容する）。
    public static let reconcileBounds = CGSize(width: 1600, height: 1000)

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    private struct StoredState: Codable {
        let schemaVersion: Int
        let state: GridLayoutState
    }

    public func saveState(_ state: GridLayoutState) {
        guard Self.isValid(state), let data = try? JSONEncoder().encode(StoredState(schemaVersion: 1, state: state)) else { return }
        userDefaults.set(data, forKey: Self.stateStorageKey)
    }

    public func loadState() -> GridLayoutState {
        if userDefaults.object(forKey: Self.stateStorageKey) != nil {
            guard let data = userDefaults.data(forKey: Self.stateStorageKey),
                  let saved = try? JSONDecoder().decode(StoredState.self, from: data),
                  saved.schemaVersion == 1, Self.isValid(saved.state) else {
                return .automatic(previousCustom: nil)
            }
            return saved.state
        }
        guard let tree = load() else { return .automatic(previousCustom: nil) }
        return .custom(CustomGridLayout(tree: tree, presetState: loadPresetState()))
    }

    private static func isValid(_ state: GridLayoutState) -> Bool {
        guard let size = state.customLayout?.canvasMinimum else { return true }
        return size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0
    }

    /// 保存に失敗しても throw しない（レイアウトは失っても復旧可能な副次情報のため）。
    public func save(_ tree: PaneTree) {
        guard let data = try? JSONEncoder().encode(tree) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    /// 壊れたデータ・未知の schemaVersion は nil を返す（既定へフォールバックさせる）。
    /// `PaneTree.init(from:)` が schemaVersion 不一致で throw するため、`try?` だけで足りる。
    public func load() -> PaneTree? {
        if userDefaults.object(forKey: Self.stateStorageKey) != nil { return loadState().customLayout?.tree }
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(PaneTree.self, from: data)
    }

    public func savePresetState(_ state: PresetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.presetStorageKey)
    }

    /// 記録が無いのに配置だけ保存されている（プリセット名を記録する前の版で並べた）なら、
    /// バランスの配置と同じかどうかで「調整済み」を決める。
    public func loadPresetState() -> PresetState {
        if userDefaults.object(forKey: Self.stateStorageKey) != nil { return loadState().customLayout?.presetState ?? .init() }
        guard let data = userDefaults.data(forKey: Self.presetStorageKey),
              let state = try? JSONDecoder().decode(PresetState.self, from: data) else {
            guard let saved = load() else { return PresetState() }
            return PresetState(isAdjusted: saved != PaneLayoutPreset.balanced.tree(for: saved.sessions))
        }
        return state
    }
}
