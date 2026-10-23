import Foundation

/// Display cells and input encoding modes, deliberately excluding the stream parser state.
public struct RuntimeDisplaySnapshot: Codable, Sendable, Equatable {
    public struct Image: Codable, Sendable, Equatable, Hashable {
        public let contentID: String
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let column: Int
        public let kitty: Bool
        public let imageID: UInt32?
        public let imageNumber: UInt32?
        public let placementID: UInt32?
        public let zIndex: Int
        public let placementColumn: Int
        public let placementRow: Int
        public let placementColumns: Int
        public let placementRows: Int
        public let pixelOffsetX: Int
        public let pixelOffsetY: Int
    }

    public struct Cell: Codable, Sendable, Equatable {
        public let text: String
        public let width: Int8
        public let attribute: Attribute
        public let hyperlink: String?
    }

    public struct Line: Codable, Sendable, Equatable {
        public let cells: [Cell]
        public let wrapped: Bool
        public let renderMode: Int
        public let images: [Image]

        private enum CodingKeys: String, CodingKey { case data, wrapped, renderMode, images }

        init(cells: [Cell], wrapped: Bool, renderMode: Int, images: [Image] = []) {
            self.cells = cells
            self.wrapped = wrapped
            self.renderMode = renderMode
            self.images = images
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var bytes = Data()
            func color(_ value: Attribute.Color?) {
                switch value {
                case .defaultColor: bytes.append(contentsOf: [0, 0, 0, 0])
                case .defaultInvertedColor: bytes.append(contentsOf: [1, 0, 0, 0])
                case .ansi256(let value): bytes.append(contentsOf: [2, value, 0, 0])
                case .trueColor(let r, let g, let b): bytes.append(contentsOf: [3, r, g, b])
                case nil: bytes.append(contentsOf: [255, 0, 0, 0])
                }
            }
            func text(_ value: String?) throws {
                guard let value else { bytes.append(contentsOf: [255, 255]); return }
                let utf8 = Array(value.utf8)
                guard utf8.count <= RuntimeDisplaySnapshot.maximumCellTextBytes else { throw InvalidSnapshot.cell }
                bytes.append(UInt8(utf8.count & 255))
                bytes.append(UInt8(utf8.count >> 8))
                bytes.append(contentsOf: utf8)
            }
            for cell in cells {
                bytes.append(UInt8(bitPattern: cell.width))
                color(cell.attribute.fg)
                color(cell.attribute.bg)
                bytes.append(cell.attribute.style.rawValue)
                bytes.append(cell.attribute.underlineStyle.rawValue)
                color(cell.attribute.underlineColor)
                try text(cell.text)
                try text(cell.hyperlink)
            }
            try container.encode(bytes, forKey: .data)
            try container.encode(wrapped, forKey: .wrapped)
            try container.encode(renderMode, forKey: .renderMode)
            try container.encode(images, forKey: .images)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let data = try container.decode(Data.self, forKey: .data)
            guard data.count <= RuntimeDisplaySnapshot.maximumTextBytes + RuntimeDisplaySnapshot.maximumDimension * 19 else {
                throw InvalidSnapshot.textLimit
            }
            let bytes = Array(data)
            var offset = 0
            func byte() throws -> UInt8 {
                guard offset < bytes.count else { throw InvalidSnapshot.cell }
                defer { offset += 1 }
                return bytes[offset]
            }
            func color() throws -> Attribute.Color? {
                let kind = try byte(), r = try byte(), g = try byte(), b = try byte()
                switch kind {
                case 0: return .defaultColor
                case 1: return .defaultInvertedColor
                case 2: return .ansi256(code: r)
                case 3: return .trueColor(red: r, green: g, blue: b)
                case 255: return nil
                default: throw InvalidSnapshot.cell
                }
            }
            func text() throws -> String? {
                let length = Int(try byte()) | Int(try byte()) << 8
                if length == 65535 { return nil }
                guard length <= RuntimeDisplaySnapshot.maximumCellTextBytes,
                      length <= bytes.count - offset else { throw InvalidSnapshot.cell }
                defer { offset += length }
                guard let value = String(bytes: bytes[offset..<offset + length], encoding: .utf8) else {
                    throw InvalidSnapshot.cell
                }
                return value
            }
            var cells: [Cell] = []
            while offset < bytes.count {
                guard cells.count < RuntimeDisplaySnapshot.maximumDimension else { throw InvalidSnapshot.lines }
                let width = Int8(bitPattern: try byte())
                guard let fg = try color(), let bg = try color() else { throw InvalidSnapshot.cell }
                let style = CharacterStyle(rawValue: try byte())
                guard let underlineStyle = UnderlineStyle(rawValue: try byte()) else { throw InvalidSnapshot.cell }
                let underlineColor = try color()
                guard let value = try text() else { throw InvalidSnapshot.cell }
                cells.append(Cell(text: value, width: width,
                    attribute: Attribute(fg: fg, bg: bg, style: style,
                        underlineStyle: underlineStyle, underlineColor: underlineColor), hyperlink: try text()))
            }
            self.cells = cells
            wrapped = try container.decode(Bool.self, forKey: .wrapped)
            renderMode = try container.decode(Int.self, forKey: .renderMode)
            images = try container.decode([Image].self, forKey: .images)
        }
    }

    public enum InvalidSnapshot: Error {
        case dimensions, lines, cursor, modes, cell, textLimit, images
    }

    public static let maximumDimension = 1024
    public static let maximumLines = 4000
    public static let maximumCells = 1_048_576
    public static let maximumTextBytes = 8 * 1024 * 1024
    public static let maximumCellTextBytes = 4096

    public let columns: Int
    public let rows: Int
    public let lines: [Line]
    public let firstLine: Int
    public let cursorColumn: Int
    public let cursorRow: Int
    public let alternateScreen: Bool
    public let cursorHidden: Bool
    public let cursorStyle: CursorStyle
    public let applicationCursor: Bool
    public let applicationKeypad: Bool
    public let bracketedPaste: Bool
    public let focusReporting: Bool
    public let mouseMode: Int
    public let mouseEncoding: Int
    public let keyboardFlags: Int
    public let lineFeedMode: Bool
    public let send8bit: Bool
    public let virtualPlacements: [KittyPlacementRecord]
    public let virtualImageContents: [UInt32: String]
    public let truncated: Bool

    public func validate() throws {
        guard !truncated else { throw InvalidSnapshot.dimensions }
        guard virtualPlacements.count <= 16384, virtualImageContents.count <= 16384 else {
            throw InvalidSnapshot.images
        }
        var placementIDs = Set<KittyPlacementKey>()
        for placement in virtualPlacements {
            guard placement.isVirtual, placement.isAlternateBuffer == alternateScreen,
                  virtualImageContents[placement.imageId] != nil,
                  placementIDs.insert(KittyPlacementKey(imageId: placement.imageId, placementId: placement.placementId)).inserted,
                  (-65536...65536).contains(placement.col), (-1_000_000...1_000_000).contains(placement.row),
                  (0...65536).contains(placement.cols), (0...65536).contains(placement.rows),
                  (-65536...65536).contains(placement.pixelOffsetX),
                  (-65536...65536).contains(placement.pixelOffsetY) else { throw InvalidSnapshot.images }
        }
        for contentID in virtualImageContents.values {
            guard contentID.utf8.count == 64,
                  contentID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw InvalidSnapshot.images
            }
        }
        guard (1...Self.maximumDimension).contains(columns),
              (1...Self.maximumDimension).contains(rows) else { throw InvalidSnapshot.dimensions }
        guard (rows...Self.maximumLines).contains(lines.count),
              firstLine >= 0, firstLine <= Int.max - lines.count else { throw InvalidSnapshot.lines }
        guard (0...columns).contains(cursorColumn), (0..<rows).contains(cursorRow) else {
            throw InvalidSnapshot.cursor
        }
        guard (0...4).contains(mouseMode), (0...4).contains(mouseEncoding),
              keyboardFlags >= 0, keyboardFlags & ~KittyKeyboardFlags.knownMask == 0 else {
            throw InvalidSnapshot.modes
        }
        var cells = 0
        var textBytes = 0
        var images = 0
        for line in lines {
            images += line.images.count
            guard images <= 16384 else { throw InvalidSnapshot.images }
            for image in line.images {
                guard image.contentID.utf8.count == 64,
                      image.contentID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                      (1...65536).contains(image.pixelWidth), (1...65536).contains(image.pixelHeight),
                      (0...Self.maximumDimension).contains(image.column),
                      (-65536...65536).contains(image.pixelOffsetX), (-65536...65536).contains(image.pixelOffsetY),
                      (-65536...65536).contains(image.placementColumn), (-1_000_000...1_000_000).contains(image.placementRow),
                      (0...65536).contains(image.placementColumns),
                      (0...65536).contains(image.placementRows) else { throw InvalidSnapshot.images }
            }
            guard !line.cells.isEmpty, line.cells.count <= columns, (0...3).contains(line.renderMode) else {
                throw InvalidSnapshot.lines
            }
            cells += line.cells.count
            guard cells <= Self.maximumCells else { throw InvalidSnapshot.lines }
            for cell in line.cells {
                let size = cell.text.utf8.count
                guard (0...2).contains(cell.width), cell.text.count == 1,
                      size <= Self.maximumCellTextBytes,
                      (cell.hyperlink?.utf8.count ?? 0) <= Self.maximumCellTextBytes else {
                    throw InvalidSnapshot.cell
                }
                textBytes += size + (cell.hyperlink?.utf8.count ?? 0)
                guard textBytes <= Self.maximumTextBytes else { throw InvalidSnapshot.textLimit }
            }
        }
    }
}
