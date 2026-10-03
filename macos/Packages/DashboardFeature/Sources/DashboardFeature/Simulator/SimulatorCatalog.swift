import Foundation
import Darwin

struct SimulatorDevice: Equatable, Sendable, Identifiable {
    let udid: String
    let name: String
    let runtimeIdentifier: String
    let state: String

    var id: String { udid }
    var isBooted: Bool { state == "Booted" }
    var runtimeLabel: String {
        "iOS " + (runtimeIdentifier.components(separatedBy: "iOS-").last?.replacingOccurrences(of: "-", with: ".") ?? runtimeIdentifier)
    }
    var stateLabel: String { isBooted ? "起動済み" : state == "Booting" ? "起動中" : "停止中" }
}

struct SimulatorCatalog: Sendable {
    struct Listing: Equatable, Sendable {
        let devices: [SimulatorDevice]
        let reason: String?
        var diagnosticReason: String? = nil
    }

    struct CommandResult: Sendable {
        let status: Int32
        let output: Data
        let errorOutput: Data
    }

    enum CommandError: LocalizedError {
        case failed(status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case let .failed(status, message): "simctl が終了コード \(status) で失敗しました: \(message)"
            }
        }
    }

    private let run: @Sendable ([String], Data?) async throws -> CommandResult
    private let isXcodeAvailable: @Sendable () async throws -> Bool

    init(run: @escaping @Sendable ([String], Data?) async throws -> CommandResult = { arguments, input in
        try await Task.detached {
            try Self.runCommand("/usr/bin/xcrun", arguments: ["simctl"] + arguments, input: input)
        }.value
    }) {
        self.init(isXcodeAvailable: Self.xcodeAvailable, run: run)
    }

    init(isXcodeAvailable: @escaping @Sendable () async throws -> Bool,
         run: @escaping @Sendable ([String], Data?) async throws -> CommandResult) {
        self.run = run
        self.isXcodeAvailable = isXcodeAvailable
    }

    private static func xcodeAvailable() async throws -> Bool {
        try await Task.detached {
            let result = try Self.runCommand("/usr/bin/xcrun", arguments: ["--find", "simctl"], input: nil)
            let path = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return result.status == 0 && FileManager.default.isExecutableFile(atPath: path)
        }.value
    }

    func list() async -> Listing {
        do {
            return Self.parse(try await execute(["list", "-j", "devices"]).output)
        } catch {
            let diagnostic = error.localizedDescription
            do {
                if try await !isXcodeAvailable() {
                    return Listing(devices: [], reason: "Xcode が見つかりません", diagnosticReason: diagnostic)
                }
            } catch {
                return Listing(devices: [], reason: "端末一覧を取得できません: \(diagnostic)",
                               diagnosticReason: "\(diagnostic)\nXcode の確認に失敗しました: \(error.localizedDescription)")
            }
            return Listing(devices: [], reason: "端末一覧を取得できません: \(diagnostic)", diagnosticReason: diagnostic)
        }
    }

    func boot(udid: String) async throws {
        _ = try await execute(["boot", udid])
    }

    func shutdown(udid: String) async throws {
        _ = try await execute(["shutdown", udid])
    }

    func screenshot(udid: String, destination: URL) async throws {
        _ = try await execute(["io", udid, "screenshot", destination.path])
    }

    func copyPasteboard(udid: String, text: String) async throws {
        _ = try await execute(["pbcopy", udid], input: Data(text.utf8))
    }

    static func parse(_ data: Data) -> Listing {
        do {
            let decoded = try JSONDecoder().decode(DeviceList.self, from: data)
            let devices = decoded.devices.flatMap { runtime, devices in
                guard runtime.hasPrefix("com.apple.CoreSimulator.SimRuntime.iOS-") else {
                    return [SimulatorDevice]()
                }
                return devices.filter(\.isAvailable).map {
                    SimulatorDevice(udid: $0.udid, name: $0.name, runtimeIdentifier: runtime, state: $0.state)
                }
            }.sorted {
                if $0.isBooted != $1.isBooted { return $0.isBooted }
                if $0.name != $1.name { return $0.name < $1.name }
                if $0.runtimeIdentifier != $1.runtimeIdentifier { return $0.runtimeIdentifier < $1.runtimeIdentifier }
                return $0.udid < $1.udid
            }
            return Listing(devices: devices, reason: nil)
        } catch {
            return Listing(devices: [], reason: "端末一覧のJSONを解析できません: \(error.localizedDescription)")
        }
    }

    private struct DeviceList: Decodable {
        let devices: [String: [Device]]

        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let isAvailable: Bool
        }
    }

    private func execute(_ arguments: [String], input: Data? = nil) async throws -> CommandResult {
        let result = try await run(arguments, input)
        guard result.status == 0 else {
            throw CommandError.failed(
                status: result.status,
                message: String(decoding: result.errorOutput.isEmpty ? result.output : result.errorOutput, as: UTF8.self)
            )
        }
        return result
    }

    // WorkingTreeService.runGitと同様、両方の出力を並行して読み、パイプの詰まりを防ぐ。
    private static func runCommand(_ executable: String, arguments: [String], input: Data?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errorOutput = Pipe()
        let standardInput = input == nil ? nil : Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        process.standardInput = standardInput ?? FileHandle.nullDevice
        if let standardInput,
           fcntl(standardInput.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == -1 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try process.run()
        try output.fileHandleForWriting.close()
        try errorOutput.fileHandleForWriting.close()

        let outputCapture = DataCapture()
        let errorCapture = DataCapture()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCapture.store(output.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCapture.store(errorOutput.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        var inputError: Error?
        if let input, let standardInput {
            do {
                try standardInput.fileHandleForWriting.write(contentsOf: input)
            } catch {
                // 書き込みを諦めてもsimctlを終了させず、終了コードと標準エラーを回収する。
                inputError = error
            }
            try standardInput.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        readers.wait()
        if process.terminationStatus == 0, let inputError { throw inputError }
        return CommandResult(status: process.terminationStatus, output: outputCapture.value(), errorOutput: errorCapture.value())
    }

    private final class DataCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ data: Data) {
            lock.withLock { self.data = data }
        }

        func value() -> Data {
            lock.withLock { data }
        }
    }
}
