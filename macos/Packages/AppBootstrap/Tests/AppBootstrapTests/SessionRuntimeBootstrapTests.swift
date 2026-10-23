import Darwin
import Foundation
import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimeBootstrapTests {
    @Test func launchRoleRequiresTheInternalArgument() {
        #expect(SessionRuntimeLaunchRole(arguments: ["Phlox"]) == .graphical)
        #expect(SessionRuntimeLaunchRole(arguments: ["Phlox", "--session-runtime"]) == .sessionRuntime)
        #expect(SessionRuntimeLaunchRole(arguments: ["Phlox", "--session-runtime-other"]) == .graphical)
    }

    @Test func locatorUsesTheExplicitStore() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let store = fixture.root.appendingPathComponent("store", isDirectory: true)
        #expect(try SessionRuntimeLease.resolvedStoreURL(environment: ["PHLOX_DATA_DIR": store.path])
            == store.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test func onlyOneLeaseCanOwnAStore() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        var first: SessionRuntimeLease? = try SessionRuntimeLease(storeURL: fixture.root)
        #expect(first != nil)
        #expect(throws: SessionRuntimeBootstrapError.alreadyOwned) {
            _ = try SessionRuntimeLease(storeURL: fixture.root)
        }
        first = nil
        let next = try SessionRuntimeLease(storeURL: fixture.root)
        #expect(next.storeURL == fixture.root.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test func differentStoresCanBeOwnedTogether() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let a = try SessionRuntimeLease(storeURL: fixture.root.appendingPathComponent("a"))
        let b = try SessionRuntimeLease(storeURL: fixture.root.appendingPathComponent("b"))
        #expect(a.directoryURL != b.directoryURL)
        withExtendedLifetime((a, b)) {}
    }

    @Test func canonicalAliasesShareOwnership() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let store = fixture.root.appendingPathComponent("store")
        let owner = try SessionRuntimeLease(storeURL: store)
        let alias = fixture.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: store)
        #expect(throws: SessionRuntimeBootstrapError.alreadyOwned) {
            _ = try SessionRuntimeLease(storeURL: alias)
        }
        withExtendedLifetime(owner) {}
    }

    @Test func discoveryRoundTripsWithPrivatePermissionsAndReplacesThePreviousGeneration() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let owner = try SessionRuntimeLease(storeURL: fixture.root)
        let first = SessionRuntimeDiscovery(storeURL: owner.storeURL, assetsRoot: fixture.root)
        try owner.publish(first)
        #expect(try SessionRuntimeLease.readDiscovery(storeURL: fixture.root) == first)
        var ready = SessionRuntimeDiscovery(storeURL: owner.storeURL, assetsRoot: fixture.root)
        ready.state = .ready
        ready.controlURL = URL(string: "http://127.0.0.1:12345")
        ready.interactionFailure = "Worktree recreation requires graphical confirmation"
        try owner.publish(ready)
        #expect(try SessionRuntimeLease.readDiscovery(storeURL: fixture.root) == ready)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: owner.directoryURL.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: owner.discoveryURL.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let files = try FileManager.default.contentsOfDirectory(atPath: owner.directoryURL.path).sorted()
        #expect(files == ["discovery.json", "host.lock"])
    }

    @Test func discoveryDoesNotReplaceTheOwnershipLock() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let owner = try SessionRuntimeLease(storeURL: fixture.root)
        #expect(try SessionRuntimeLease.readDiscovery(storeURL: fixture.root) == nil)
        #expect(throws: SessionRuntimeBootstrapError.alreadyOwned) {
            _ = try SessionRuntimeLease(storeURL: fixture.root)
        }
        withExtendedLifetime(owner) {}
    }

    @Test func wrongStoreCannotBePublished() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let owner = try SessionRuntimeLease(storeURL: fixture.root)
        let metadata = SessionRuntimeDiscovery(
            storeURL: fixture.root.appendingPathComponent("other"), assetsRoot: fixture.root
        )
        #expect(throws: SessionRuntimeBootstrapError.wrongStore) { try owner.publish(metadata) }
    }

    @Test func runtimeDirectorySymlinksAreRejected() throws {
        let fixture = try RuntimeStoreFixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = fixture.root.appendingPathComponent("session-runtime")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: SessionRuntimeBootstrapError.unsafeFile(link.path)) {
            _ = try SessionRuntimeLease(storeURL: fixture.root)
        }
    }
}

private struct RuntimeStoreFixture {
    let root: URL

    init() throws {
        let projectRoot = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in
            url.deletingLastPathComponent()
        }
        root = projectRoot.appendingPathComponent(".verification/runtime-host-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("Owner: SessionRuntimeBootstrapTests. Purpose: isolated runtime metadata and lock fixtures. No child processes.\n".utf8)
            .write(to: root.appendingPathComponent("ownership.txt"))
    }

    func remove() {
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("Runtime test fixture cleanup failed: \(error)") }
    }
}
