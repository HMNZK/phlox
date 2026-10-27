import CryptoKit
import Foundation

do {
    let args = CommandLine.arguments
    guard args.count == 4,
          let signature = Data(base64Encoded: args[2]), signature.count == 64,
          let publicKey = Data(base64Encoded: args[3]), publicKey.count == 32 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let zip = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: zip) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    print("Distribution ZIP Ed25519 signature verified with the DMG app public key.")
} catch {
    fputs("Sparkle signature verification failed: \(error)\n", stderr)
    exit(1)
}
