import Foundation
import Network
import Testing
@testable import LocalHTTPServer

private final class ParametersBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: NWParameters?
    func set(_ value: NWParameters) { lock.withLock { stored = value } }
    var value: NWParameters? { lock.withLock { stored } }
}

/// 計画的なホスト更新では、旧ホストが閉じた固定ポートを新ホストが束縛する。TIME_WAITで失敗しないよう再利用を許す。
@Test func fixedPortListenerAllowsLocalEndpointReuse() throws {
    let box = ParametersBox()
    _ = try LocalHTTPListener.makeListener(port: 45_871, make: { parameters in
        box.set(parameters)
        return try NWListener(using: .tcp)
    })
    #expect(box.value?.allowLocalEndpointReuse == true)
}

@Test func randomPortListenerKeepsTheDefaultReuse() throws {
    let box = ParametersBox()
    _ = try LocalHTTPListener.makeListener(port: 0, make: { parameters in
        box.set(parameters)
        return try NWListener(using: .tcp)
    })
    #expect(box.value?.allowLocalEndpointReuse == false)
}
