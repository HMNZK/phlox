import Foundation
import AgentDomain

public struct SessionGridArrangement: Equatable, Codable, Sendable {
    public struct Region: Hashable, Codable, Sendable {
        public let anchor: Int
        public let rowSpan: Int
        public let colSpan: Int

        public init(anchor: Int, rowSpan: Int, colSpan: Int) {
            self.anchor = anchor
            self.rowSpan = rowSpan
            self.colSpan = colSpan
        }
    }

    public let size: Int
    public private(set) var placements: [SessionID: Region]

    public init(size: Int) {
        self.size = size
        placements = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case size
        case placements
    }

    /// 復号時に不変条件（盤内・互いに素）を検証し、不正データを拒否する。
    /// これを怠ると `reconciled` が不正 Region を保持し、`placement(at:)` が重複セルで
    /// Dictionary 反復順に依存する（決定論性の破れ）ため、公開永続化入口で塞ぐ。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSize = try container.decode(Int.self, forKey: .size)
        let decodedPlacements = try container.decode([SessionID: Region].self, forKey: .placements)

        var covered = Set<Int>()
        for region in decodedPlacements.values {
            guard
                decodedSize > 0,
                region.anchor >= 0,
                region.rowSpan >= 1,
                region.colSpan >= 1
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .placements, in: container,
                    debugDescription: "invalid region dimensions"
                )
            }
            let row = region.anchor / decodedSize
            let column = region.anchor % decodedSize
            guard
                row < decodedSize,
                row + region.rowSpan <= decodedSize,
                column + region.colSpan <= decodedSize
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .placements, in: container,
                    debugDescription: "region out of bounds"
                )
            }
            for r in row..<(row + region.rowSpan) {
                for c in column..<(column + region.colSpan) {
                    guard covered.insert(r * decodedSize + c).inserted else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .placements, in: container,
                            debugDescription: "overlapping regions"
                        )
                    }
                }
            }
        }

        size = decodedSize
        placements = decodedPlacements
    }

    public func reconciled(with visibleSessions: [SessionID]) -> SessionGridArrangement {
        let visibleSet = Set(visibleSessions)
        var result = self
        result.placements = placements.filter { visibleSet.contains($0.key) }

        for id in visibleSessions where result.placements[id] == nil {
            guard let cell = result.firstFreeCell() else { break }
            result.placements[id] = Region(anchor: cell, rowSpan: 1, colSpan: 1)
        }

        return result
    }

    public func move(_ id: SessionID, toCell cell: Int) -> SessionGridArrangement? {
        guard placements[id] != nil, isFree(cell: cell) else { return nil }

        var result = self
        result.placements[id] = Region(anchor: cell, rowSpan: 1, colSpan: 1)
        return result
    }

    public func swap(_ a: SessionID, _ b: SessionID) -> SessionGridArrangement? {
        guard let first = placements[a], let second = placements[b] else { return nil }

        var result = self
        result.placements[a] = second
        result.placements[b] = first
        return result
    }

    public func canMergeRight(_ id: SessionID) -> Bool {
        merge(id, direction: .right) != nil
    }

    public func canMergeDown(_ id: SessionID) -> Bool {
        merge(id, direction: .down) != nil
    }

    public func mergeRight(_ id: SessionID) -> SessionGridArrangement? {
        merge(id, direction: .right)
    }

    public func mergeDown(_ id: SessionID) -> SessionGridArrangement? {
        merge(id, direction: .down)
    }

    public func unmerge(_ id: SessionID) -> SessionGridArrangement? {
        guard
            let region = placements[id],
            region.rowSpan > 1 || region.colSpan > 1
        else {
            return nil
        }

        var result = self
        result.placements[id] = Region(anchor: region.anchor, rowSpan: 1, colSpan: 1)
        return result
    }

    public func isFree(cell: Int) -> Bool {
        isValid(cell: cell) && placement(at: cell) == nil
    }

    public func placement(at cell: Int) -> (id: SessionID, region: Region)? {
        guard isValid(cell: cell) else { return nil }

        for (id, region) in placements where contains(cell, in: region) {
            return (id, region)
        }
        return nil
    }

    private enum MergeDirection {
        case right
        case down
    }

    private func merge(
        _ id: SessionID,
        direction: MergeDirection
    ) -> SessionGridArrangement? {
        guard let current = placements[id] else { return nil }

        let expanded: Region
        switch direction {
        case .right:
            expanded = Region(
                anchor: current.anchor,
                rowSpan: current.rowSpan,
                colSpan: current.colSpan + 1
            )
        case .down:
            expanded = Region(
                anchor: current.anchor,
                rowSpan: current.rowSpan + 1,
                colSpan: current.colSpan
            )
        }
        guard isValid(region: expanded) else { return nil }

        let absorbedCells = Set(cells(in: expanded)).subtracting(cells(in: current))
        let occupants = placements
            .filter { otherID, region in
                otherID != id && cells(in: region).contains(where: absorbedCells.contains)
            }
            .sorted { lhs, rhs in
                if lhs.value.anchor != rhs.value.anchor {
                    return lhs.value.anchor < rhs.value.anchor
                }
                return lhs.key.rawValue.uuidString < rhs.key.rawValue.uuidString
            }

        var result = self
        result.placements[id] = expanded
        for occupant in occupants {
            result.placements.removeValue(forKey: occupant.key)
        }

        let freeCells = result.freeCells()
        guard freeCells.count >= occupants.count else { return nil }

        for (occupant, cell) in zip(occupants, freeCells) {
            result.placements[occupant.key] = Region(anchor: cell, rowSpan: 1, colSpan: 1)
        }
        return result
    }

    private func isValid(cell: Int) -> Bool {
        guard size > 0, cell >= 0 else { return false }
        return cell / size < size
    }

    private func isValid(region: Region) -> Bool {
        guard
            size > 0,
            region.anchor >= 0,
            region.rowSpan >= 1,
            region.colSpan >= 1
        else {
            return false
        }

        let row = region.anchor / size
        let column = region.anchor % size
        return row < size
            && row + region.rowSpan <= size
            && column + region.colSpan <= size
    }

    private func contains(_ cell: Int, in region: Region) -> Bool {
        guard isValid(region: region) else { return false }

        let cellRow = cell / size
        let cellColumn = cell % size
        let anchorRow = region.anchor / size
        let anchorColumn = region.anchor % size
        return cellRow >= anchorRow
            && cellRow < anchorRow + region.rowSpan
            && cellColumn >= anchorColumn
            && cellColumn < anchorColumn + region.colSpan
    }

    private func cells(in region: Region) -> [Int] {
        guard isValid(region: region) else { return [] }

        let anchorRow = region.anchor / size
        let anchorColumn = region.anchor % size
        return (anchorRow..<(anchorRow + region.rowSpan)).flatMap { row in
            (anchorColumn..<(anchorColumn + region.colSpan)).map { column in
                row * size + column
            }
        }
    }

    private func firstFreeCell() -> Int? {
        freeCells().first
    }

    private func freeCells() -> [Int] {
        guard size > 0 else { return [] }
        return (0..<(size * size)).filter { placement(at: $0) == nil }
    }
}

public enum SessionGridAction: Equatable, Sendable {
    case moveToCell(SessionID, cell: Int)
    case swap(SessionID, SessionID)
    case mergeRight(SessionID)
    case mergeDown(SessionID)
    case unmerge(SessionID)
}
