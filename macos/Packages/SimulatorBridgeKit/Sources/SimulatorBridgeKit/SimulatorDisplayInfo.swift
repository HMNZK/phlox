import Foundation
import IOSurface

@objc public enum SimulatorOrientation: Int, Sendable, CaseIterable {
    case portrait
    case portraitUpsideDown
    // 縦画面を左・右へそれぞれ90度回転した向き。
    case landscapeLeft
    case landscapeRight
}

public final class SimulatorBridgeCapability: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    public let protocolVersion: Int
    public let helperBuild: String
    public let xcodeBuild: String
    public let coreSimulatorLoaded: Bool
    public let simulatorKitLoaded: Bool
    public let reason: String?

    public init(
        protocolVersion: Int, helperBuild: String, xcodeBuild: String,
        coreSimulatorLoaded: Bool, simulatorKitLoaded: Bool, reason: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.helperBuild = helperBuild
        self.xcodeBuild = xcodeBuild
        self.coreSimulatorLoaded = coreSimulatorLoaded
        self.simulatorKitLoaded = simulatorKitLoaded
        self.reason = reason
    }

    public required convenience init?(coder: NSCoder) {
        guard let helperBuild = coder.decodeObject(of: NSString.self, forKey: "helperBuild") as String?,
              let xcodeBuild = coder.decodeObject(of: NSString.self, forKey: "xcodeBuild") as String?,
              ["protocolVersion", "coreSimulatorLoaded", "simulatorKitLoaded"].allSatisfy(coder.containsValue(forKey:))
        else { return nil }
        self.init(
            protocolVersion: coder.decodeInteger(forKey: "protocolVersion"),
            helperBuild: helperBuild, xcodeBuild: xcodeBuild,
            coreSimulatorLoaded: coder.decodeBool(forKey: "coreSimulatorLoaded"),
            simulatorKitLoaded: coder.decodeBool(forKey: "simulatorKitLoaded"),
            reason: coder.containsValue(forKey: "reason")
                ? coder.decodeObject(of: NSString.self, forKey: "reason") as String? : nil
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(protocolVersion, forKey: "protocolVersion")
        coder.encode(helperBuild as NSString, forKey: "helperBuild")
        coder.encode(xcodeBuild as NSString, forKey: "xcodeBuild")
        coder.encode(coreSimulatorLoaded, forKey: "coreSimulatorLoaded")
        coder.encode(simulatorKitLoaded, forKey: "simulatorKitLoaded")
        if let reason { coder.encode(reason as NSString, forKey: "reason") }
    }
}

public final class SimulatorDisplayInfo: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    public let udid: String
    public let connectionGeneration: Int
    public let displayGeneration: Int
    public let surface: IOSurface
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let orientation: SimulatorOrientation
    public let surfaceIsRotated: Bool
    public let pixelFormat: UInt32

    public init(
        udid: String, connectionGeneration: Int, displayGeneration: Int, surface: IOSurface,
        pixelWidth: Int, pixelHeight: Int, orientation: SimulatorOrientation,
        surfaceIsRotated: Bool, pixelFormat: UInt32
    ) {
        self.udid = udid
        self.connectionGeneration = connectionGeneration
        self.displayGeneration = displayGeneration
        self.surface = surface
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.orientation = orientation
        self.surfaceIsRotated = surfaceIsRotated
        self.pixelFormat = pixelFormat
    }

    public required convenience init?(coder: NSCoder) {
        let keys = ["connectionGeneration", "displayGeneration", "pixelWidth", "pixelHeight",
                    "orientation", "surfaceIsRotated", "pixelFormat"]
        guard keys.allSatisfy(coder.containsValue(forKey:)),
              let udid = coder.decodeObject(of: NSString.self, forKey: "udid") as String?, !udid.isEmpty,
              let surface = coder.decodeObject(of: IOSurface.self, forKey: "surface"),
              let orientation = SimulatorOrientation(rawValue: coder.decodeInteger(forKey: "orientation")),
              coder.decodeInteger(forKey: "connectionGeneration") >= 0,
              coder.decodeInteger(forKey: "displayGeneration") >= 0,
              coder.decodeInteger(forKey: "pixelWidth") > 0,
              coder.decodeInteger(forKey: "pixelHeight") > 0,
              let pixelFormat = UInt32(exactly: coder.decodeInt64(forKey: "pixelFormat"))
        else { return nil }
        self.init(
            udid: udid, connectionGeneration: coder.decodeInteger(forKey: "connectionGeneration"),
            displayGeneration: coder.decodeInteger(forKey: "displayGeneration"), surface: surface,
            pixelWidth: coder.decodeInteger(forKey: "pixelWidth"), pixelHeight: coder.decodeInteger(forKey: "pixelHeight"),
            orientation: orientation, surfaceIsRotated: coder.decodeBool(forKey: "surfaceIsRotated"),
            pixelFormat: pixelFormat
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(udid as NSString, forKey: "udid")
        coder.encode(connectionGeneration, forKey: "connectionGeneration")
        coder.encode(displayGeneration, forKey: "displayGeneration")
        coder.encode(surface, forKey: "surface")
        coder.encode(pixelWidth, forKey: "pixelWidth")
        coder.encode(pixelHeight, forKey: "pixelHeight")
        coder.encode(orientation.rawValue, forKey: "orientation")
        coder.encode(surfaceIsRotated, forKey: "surfaceIsRotated")
        coder.encode(Int64(pixelFormat), forKey: "pixelFormat")
    }

    public func isCurrent(udid: String, connectionGeneration: Int, minimumDisplayGeneration: Int) -> Bool {
        self.udid == udid && self.connectionGeneration == connectionGeneration
            && displayGeneration >= minimumDisplayGeneration
    }
}
