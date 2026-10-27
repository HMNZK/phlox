// Synthetic native packaging fixture. The ephemeral private key never leaves this process.
import CryptoKit
import Foundation

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
}

let files = FileManager.default
let build = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let app = build.appendingPathComponent("Phlox.app")
try files.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
try files.createDirectory(at: output, withIntermediateDirectories: true)
try files.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/Phlox").path)
let key = Curve25519.Signing.PrivateKey()
let info = ["CFBundleIdentifier": "test.phlox.distribution", "CFBundleName": "Phlox",
            "CFBundleExecutable": "Phlox", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "2", "CFBundleShortVersionString": "1",
            "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString()]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: app.appendingPathComponent("Contents/Info.plist"))
try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
let zip = output.appendingPathComponent("Phlox-1.zip")
try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
try run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", build.path, "-volname", "Gate Fixture", "-format", "UDZO", output.appendingPathComponent("Phlox.dmg").path])
let signature = try key.signature(for: Data(contentsOf: zip)).base64EncodedString()
try JSONSerialization.data(withJSONObject: ["signature": signature], options: .sortedKeys)
    .write(to: output.appendingPathComponent("signature.json"))
