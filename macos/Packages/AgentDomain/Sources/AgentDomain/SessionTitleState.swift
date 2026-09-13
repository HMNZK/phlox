import Foundation

public enum SessionTitleSource: String, Codable, Hashable, Sendable {
    case flower
    case derived
    case manual
}

public struct SessionTitleState: Equatable, Sendable {
    public let name: String
    public let source: SessionTitleSource
    public let flowerName: String?
    public let fullDerivedTitle: String?

    public init(
        name: String,
        source: SessionTitleSource,
        flowerName: String?,
        fullDerivedTitle: String?
    ) {
        let trimmedFlower = flowerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let flower = (trimmedFlower?.isEmpty == false) ? trimmedFlower : nil
        switch source {
        case .manual:
            self.name = name
            self.source = .manual
            self.flowerName = flower
            self.fullDerivedTitle = nil
        case .flower:
            if let flower, name == flower, fullDerivedTitle == nil {
                self.name = name
                self.source = .flower
                self.flowerName = flower
                self.fullDerivedTitle = nil
            } else {
                self.name = name
                self.source = .manual
                self.flowerName = flower
                self.fullDerivedTitle = nil
            }
        case .derived:
            if let fullDerivedTitle,
               let derived = SessionTitleDeriver.derive(from: fullDerivedTitle),
               derived.fullTitle == fullDerivedTitle,
               derived.title == name {
                self.name = name
                self.source = .derived
                self.flowerName = flower
                self.fullDerivedTitle = fullDerivedTitle
            } else {
                self.name = name
                self.source = .manual
                self.flowerName = flower
                self.fullDerivedTitle = nil
            }
        }
    }

    public static func generated(flowerName: String) -> Self {
        let trimmed = flowerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            name: trimmed,
            source: .flower,
            flowerName: trimmed,
            fullDerivedTitle: nil
        )
    }

    public static func legacy(name: String) -> Self {
        Self(
            name: name,
            source: .manual,
            flowerName: nil,
            fullDerivedTitle: nil
        )
    }

    public func receivingUserMessage(_ text: String) -> Self {
        guard source == .flower else { return self }
        guard let derived = SessionTitleDeriver.derive(from: text) else { return self }
        return SessionTitleState(
            name: derived.title,
            source: .derived,
            flowerName: flowerName,
            fullDerivedTitle: derived.fullTitle
        )
    }

    public func renamed(to name: String) -> Self {
        SessionTitleState(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual,
            flowerName: flowerName,
            fullDerivedTitle: nil
        )
    }

    public func effectiveName(fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
