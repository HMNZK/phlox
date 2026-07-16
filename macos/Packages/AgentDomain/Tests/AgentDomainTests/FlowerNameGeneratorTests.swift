import Testing
@testable import AgentDomain

// 個数は固定しない(名前の増減で壊れるため)。avoiding の正規化(trim+小文字化)で
// 衝突しないことだけを不変条件として守る。
@Test func flowerNameGenerator_namesAreNonEmptyAndUniqueAfterNormalization() {
    #expect(!FlowerNameGenerator.names.isEmpty)

    let normalized = FlowerNameGenerator.names.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    #expect(Set(normalized).count == FlowerNameGenerator.names.count)
    #expect(normalized.allSatisfy { !$0.isEmpty })
}

@Test func flowerNameGenerator_random_picksFirstAvailableWithDeterministicPick() {
    let name = FlowerNameGenerator.random(avoiding: [], using: { _ in 0 })
    #expect(name == FlowerNameGenerator.names[0])
}

@Test func flowerNameGenerator_random_avoidsUsedIncludingTrimAndCase() {
    let used: Set<String> = [
        "  rose ",
        "TULIP",
        FlowerNameGenerator.names[2],
    ]
    let name = FlowerNameGenerator.random(avoiding: used, using: { _ in 0 })
    #expect(name == FlowerNameGenerator.names[3])
}

@Test func flowerNameGenerator_random_addsNumberedSuffixWhenAllBaseNamesUsed() {
    let used = Set(FlowerNameGenerator.names)
    let name = FlowerNameGenerator.random(avoiding: used, using: { _ in 0 })
    #expect(name == "Rose 2")
}

@Test func flowerNameGenerator_random_incrementsSuffixUntilNoCollision() {
    var used = Set(FlowerNameGenerator.names)
    used.insert("Rose 2")
    used.insert("  rose   2  ")
    let name = FlowerNameGenerator.random(avoiding: used, using: { _ in 0 })
    #expect(name == "Rose 3")
}
