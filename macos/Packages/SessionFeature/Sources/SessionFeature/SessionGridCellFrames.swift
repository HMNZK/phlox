import CoreGraphics

/// k×k 盤の各セル矩形を row-major 順で返す。
public func sessionGridCellFrames(
    size: Int,
    bounds: CGSize,
    spacing: CGFloat
) -> [CGRect] {
    guard size > 0 else { return [] }

    let gapCount = CGFloat(size - 1)
    let cellWidth = (bounds.width - gapCount * spacing) / CGFloat(size)
    let cellHeight = (bounds.height - gapCount * spacing) / CGFloat(size)

    return (0..<(size * size)).map { cell in
        let row = cell / size
        let column = cell % size
        return CGRect(
            x: CGFloat(column) * (cellWidth + spacing),
            y: CGFloat(row) * (cellHeight + spacing),
            width: cellWidth,
            height: cellHeight
        )
    }
}

/// Region が覆うセルとその内部 spacing を内包する矩形を返す。
public func sessionGridRegionRect(
    region: SessionGridArrangement.Region,
    size: Int,
    bounds: CGSize,
    spacing: CGFloat
) -> CGRect {
    guard
        size > 0,
        region.anchor >= 0,
        region.anchor < size * size,
        region.rowSpan > 0,
        region.colSpan > 0
    else {
        return .zero
    }

    let anchorRow = region.anchor / size
    let anchorColumn = region.anchor % size
    guard
        anchorRow + region.rowSpan <= size,
        anchorColumn + region.colSpan <= size
    else {
        return .zero
    }
    let anchorFrame = sessionGridCellFrames(
        size: size,
        bounds: bounds,
        spacing: spacing
    )[region.anchor]

    return CGRect(
        x: anchorFrame.minX,
        y: anchorFrame.minY,
        width: CGFloat(region.colSpan) * anchorFrame.width
            + CGFloat(region.colSpan - 1) * spacing,
        height: CGFloat(region.rowSpan) * anchorFrame.height
            + CGFloat(region.rowSpan - 1) * spacing
    )
}
