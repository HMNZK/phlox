import Foundation

@objc public protocol SimulatorBridgeProtocol {
    func probe(reply: @escaping (SimulatorBridgeCapability) -> Void)
    func attach(udid: String, generation: Int, reply: @escaping (SimulatorDisplayInfo?, NSError?) -> Void)
    func detach(udid: String)
    func sendTouch(udid: String, phase: Int, x: Double, y: Double)
    func sendScroll(udid: String, dx: Double, dy: Double, x: Double, y: Double)
    func sendKey(udid: String, keyCode: UInt16, modifiers: UInt, down: Bool)
    func sendButton(udid: String, button: Int)
    func releaseAll(udid: String)
}

@objc public protocol SimulatorBridgeClientProtocol {
    func surfaceChanged(_ info: SimulatorDisplayInfo)
}

public enum SimulatorBridgeInterfaces {
    public static let protocolVersion = 1
    public static let replyTimeout: TimeInterval = 5

    public static func service() -> NSXPCInterface {
        let interface = NSXPCInterface(with: SimulatorBridgeProtocol.self)
        interface.setClasses(
            NSSet(object: SimulatorBridgeCapability.self) as! Set<AnyHashable>,
            for: #selector(SimulatorBridgeProtocol.probe(reply:)), argumentIndex: 0, ofReply: true
        )
        interface.setClasses(
            displayClasses, for: #selector(SimulatorBridgeProtocol.attach(udid:generation:reply:)),
            argumentIndex: 0, ofReply: true
        )
        interface.setClasses(
            NSSet(object: NSError.self) as! Set<AnyHashable>,
            for: #selector(SimulatorBridgeProtocol.attach(udid:generation:reply:)),
            argumentIndex: 1, ofReply: true
        )
        return interface
    }

    public static func client() -> NSXPCInterface {
        let interface = NSXPCInterface(with: SimulatorBridgeClientProtocol.self)
        interface.setClasses(
            displayClasses, for: #selector(SimulatorBridgeClientProtocol.surfaceChanged(_:)),
            argumentIndex: 0, ofReply: false
        )
        return interface
    }

    private static var displayClasses: Set<AnyHashable> {
        NSSet(object: SimulatorDisplayInfo.self) as! Set<AnyHashable>
    }
}

/// 再接続と期限切れのたびに進め、以前の接続から届いた応答を除外する。
public struct SimulatorConnectionGeneration: Sendable {
    public private(set) var current = 0

    public init() {}

    @discardableResult
    public mutating func advance() -> Int {
        current += 1
        return current
    }

    public func accepts(_ generation: Int) -> Bool {
        generation == current
    }
}
