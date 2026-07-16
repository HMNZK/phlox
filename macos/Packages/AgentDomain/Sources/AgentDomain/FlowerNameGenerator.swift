import Foundation

public enum FlowerNameGenerator {
    public static let names: [String] = [
        "Rose", "Tulip", "Lily", "Daisy", "Iris", "Jasmine", "Lotus", "Orchid", "Poppy", "Violet",
        "Dahlia", "Marigold", "Lavender", "Peony", "Camellia", "Magnolia", "Hibiscus", "Sunflower",
        "Daffodil", "Petunia", "Begonia", "Azalea", "Bluebell", "Foxglove", "Snapdragon", "Primrose",
        "Zinnia", "Anemone", "Freesia", "Gardenia",
    ]

    public static func random(
        avoiding used: Set<String>,
        using pick: (Int) -> Int = { Int.random(in: 0 ..< $0) }
    ) -> String {
        let normalizedUsed = Set(used.map(normalize(_:)))
        let available = names.filter { !normalizedUsed.contains(normalize($0)) }

        if !available.isEmpty {
            let index = pick(available.count)
            return available[index]
        }

        let base = names[pick(names.count)]
        var suffix = 2
        while true {
            let candidate = "\(base) \(suffix)"
            if !normalizedUsed.contains(normalize(candidate)) {
                return candidate
            }
            suffix += 1
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
