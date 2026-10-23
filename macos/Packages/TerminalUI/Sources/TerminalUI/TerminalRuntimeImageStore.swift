import CryptoKit
import Darwin
import Foundation

public enum TerminalRuntimeImageError: Error, Sendable, Equatable {
    case staleReference(contentID: String)
}

@MainActor
final class TerminalRuntimeImageStore {
    enum StoreError: Error {
        case unsafeDirectory, unsafeFile, invalidContentID, invalidCapacity, capacityExceeded, readOnly, io(Int32), corruptImage
    }

    private final class CachedReference {
        weak var source: AnyObject?
        let contentID: String
        init(source: AnyObject, contentID: String) {
            self.source = source
            self.contentID = contentID
        }
    }

    private struct StoredFile {
        let bytes: Int
        var unreferencedSince: ContinuousClock.Instant?
    }

    static let maximumBytes = 320 * 1024 * 1024
    // The client discards responses after 35 seconds; retain dead-source images beyond that deadline.
    static let referenceLease: Duration = .seconds(40)
    private let directory: Int32
    private let writable: Bool
    private let capacityBytes: Int
    private let now: () -> ContinuousClock.Instant
    private var totalBytes = 0
    private var references: [ObjectIdentifier: CachedReference] = [:]
    private var files: [String: StoredFile] = [:]

    init(directory url: URL, writable: Bool, capacityBytes: Int = TerminalRuntimeImageStore.maximumBytes,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) throws {
        guard capacityBytes > 0, capacityBytes <= Self.maximumBytes else { throw StoreError.invalidCapacity }
        self.capacityBytes = capacityBytes
        self.now = now
        if writable, !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError.io(errno) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & 0o777 == 0o700 else {
            close(descriptor)
            throw StoreError.unsafeDirectory
        }
        do {
            for file in try FileManager.default.contentsOfDirectory(at: url,
                includingPropertiesForKeys: nil) {
                let name = file.lastPathComponent
                let temporary = name.hasPrefix(".image-") && UUID(uuidString: String(name.dropFirst(7))) != nil
                guard Self.isContentID(name) || temporary else { throw StoreError.unsafeDirectory }
                let fd = openat(descriptor, file.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw StoreError.unsafeFile }
                defer { close(fd) }
                var fileInfo = stat()
                guard fstat(fd, &fileInfo) == 0, Self.safe(fileInfo) else { throw StoreError.unsafeFile }
                if temporary, writable {
                    guard unlinkat(descriptor, name, 0) == 0 else { throw StoreError.io(errno) }
                    continue
                }
                guard fileInfo.st_size <= capacityBytes - totalBytes else { throw StoreError.capacityExceeded }
                totalBytes += Int(fileInfo.st_size)
                files[name] = StoredFile(bytes: Int(fileInfo.st_size), unreferencedSince: now())
            }
        } catch {
            close(descriptor)
            throw error
        }
        directory = descriptor
        self.writable = writable
    }

    deinit { close(directory) }

    func reference(source: AnyObject, encode: () throws -> Data) throws -> String {
        guard writable else { throw StoreError.readOnly }
        let identity = ObjectIdentifier(source)
        if let cached = references[identity], cached.source === source {
            files[cached.contentID]?.unreferencedSince = nil
            return cached.contentID
        }
        let data = try encode()
        let contentID = Self.digest(data)
        let existing = openat(directory, contentID, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if existing >= 0 {
            close(existing)
            guard try read(contentID) == data else { throw StoreError.corruptImage }
        } else {
            guard errno == ENOENT else { throw StoreError.io(errno) }
            if data.count > capacityBytes - totalBytes { try collectGarbage() }
            guard data.count <= capacityBytes - totalBytes else { throw StoreError.capacityExceeded }
            let temporary = ".image-\(UUID().uuidString)"
            let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw StoreError.io(errno) }
            var published = false
            defer {
                close(descriptor)
                if !published { unlinkat(directory, temporary, 0) }
            }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { throw StoreError.io(errno) }
                    offset += written
                }
            }
            guard fsync(descriptor) == 0 else { throw StoreError.io(errno) }
            guard renameatx_np(directory, temporary, directory, contentID, UInt32(RENAME_EXCL)) == 0 else {
                throw StoreError.io(errno)
            }
            published = true
            totalBytes += data.count
            files[contentID] = StoredFile(bytes: data.count, unreferencedSince: nil)
        }
        files[contentID]?.unreferencedSince = nil
        references[identity] = CachedReference(source: source, contentID: contentID)
        return contentID
    }

    func collectGarbage() throws {
        guard writable else { return }
        references = references.filter { $0.value.source != nil }
        let live = Set(references.values.map(\.contentID))
        let instant = now()
        for (contentID, file) in files {
            if live.contains(contentID) {
                files[contentID]?.unreferencedSince = nil
                continue
            }
            guard let unreferencedSince = file.unreferencedSince else {
                files[contentID]?.unreferencedSince = instant
                continue
            }
            guard instant >= unreferencedSince.advanced(by: Self.referenceLease) else { continue }
            let descriptor = openat(directory, contentID, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            if descriptor >= 0 {
                defer { close(descriptor) }
                var info = stat()
                guard fstat(descriptor, &info) == 0, Self.safe(info), info.st_size == file.bytes else {
                    throw StoreError.unsafeFile
                }
                guard unlinkat(directory, contentID, 0) == 0 else { throw StoreError.io(errno) }
            } else {
                guard errno == ENOENT else { throw StoreError.io(errno) }
            }
            files.removeValue(forKey: contentID)
            totalBytes -= file.bytes
        }
    }

    func read(_ contentID: String) throws -> Data {
        guard Self.isContentID(contentID) else { throw StoreError.invalidContentID }
        let descriptor = openat(directory, contentID, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw TerminalRuntimeImageError.staleReference(contentID: contentID) }
            throw StoreError.io(errno)
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, Self.safe(info) else { throw StoreError.unsafeFile }
        guard info.st_size <= Self.maximumBytes else { throw StoreError.capacityExceeded }
        let data = try file.readToEnd() ?? Data()
        guard data.count == info.st_size, Self.digest(data) == contentID else { throw StoreError.corruptImage }
        return data
    }

    private static func safe(_ info: stat) -> Bool {
        info.st_uid == geteuid() && info.st_mode & 0o777 == 0o600 &&
            info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1 && info.st_size >= 0
    }

    private static func isContentID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
