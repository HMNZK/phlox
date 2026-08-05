import Testing
import Foundation
@testable import AgentDomain

// MARK: - 生成（32 バイト乱数 → 64 hex）

@Test func mobileToken_generate_produces64LowercaseHexCharacters() {
    let token = MobileToken.generate()

    #expect(token.value.count == 64)
    let allowed = Set("0123456789abcdef")
    #expect(token.value.allSatisfy { allowed.contains($0) })
}

@Test func mobileToken_generate_isUniquePerCall() {
    let a = MobileToken.generate()
    let b = MobileToken.generate()

    #expect(a.value != b.value)
}

@Test func mobileToken_generate_withInjectedBytes_isDeterministicHex() {
    // 32 バイトを既知の値に固定し、hex 化が安定であることを担保。
    let bytes = [UInt8](repeating: 0xAB, count: 32)
    let token = MobileToken.generate { count in
        #expect(count == 32)
        return bytes
    }

    #expect(token.value == String(repeating: "ab", count: 32))
    #expect(token.value.count == 64)
}
