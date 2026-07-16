import Foundation
import Observation

#if os(iOS)
import AVFoundation
import Speech
#endif

public enum DSVoiceInputAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

public enum DSVoiceInputError: Error, Equatable, Sendable {
    case permissionDenied
    case unavailable
    case audioSessionFailed(String)
    case recognitionFailed(String)

    public var message: String {
        switch self {
        case .permissionDenied:
            "マイクまたは音声認識の使用が許可されていません"
        case .unavailable:
            "現在、音声入力を利用できません"
        case .audioSessionFailed(let message), .recognitionFailed(let message):
            message
        }
    }
}

public enum DSVoiceInputState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening
    case denied
    case unavailable
    case failed(String)
}

enum DSVoiceAudioFormatValidator {
    static func isValid(
        sampleRate: Double,
        channelCount: UInt32,
        isStandard: Bool = true
    ) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0 && isStandard
    }
}

struct DSVoiceRecognitionSetupState: Equatable, Sendable {
    private(set) var isStarting = false
    private(set) var isAudioSessionActive = false
    private(set) var hasInstalledAudioTap = false

    var requiresCleanup: Bool {
        isAudioSessionActive || hasInstalledAudioTap
    }

    mutating func beginStart() -> Bool {
        guard !isStarting, !requiresCleanup else { return false }
        isStarting = true
        return true
    }

    mutating func didActivateAudioSession() {
        isAudioSessionActive = true
    }

    mutating func didInstallAudioTap() {
        hasInstalledAudioTap = true
    }

    mutating func didFinishStart() {
        isStarting = false
    }

    mutating func didRemoveAudioTap() {
        hasInstalledAudioTap = false
    }

    mutating func didDeactivateAudioSession() {
        isAudioSessionActive = false
    }
}

/// Speech と録音セッションを UI・状態管理から隔離する差し替え可能な境界。
@MainActor
public protocol VoiceInputRecognizing: AnyObject {
    func authorizationStatus() -> DSVoiceInputAuthorization
    func requestAuthorization() async -> DSVoiceInputAuthorization
    func startRecognition(
        onTranscription: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (DSVoiceInputError) -> Void
    ) throws
    func stopRecognition() throws
}

@MainActor
@Observable
public final class DSVoiceInputController {
    public private(set) var state: DSVoiceInputState = .idle

    private let recognizer: any VoiceInputRecognizing
    private var inputPrefix = ""
    private var permissionRequestTask: Task<DSVoiceInputAuthorization, Never>?
    private var permissionRequestID: UUID?

    public init(recognizer: any VoiceInputRecognizing) {
        self.recognizer = recognizer
    }

    public convenience init() {
        self.init(recognizer: DSLiveVoiceInputRecognizer())
    }

    public func toggle(
        currentText: String,
        onTextChange: @escaping (String) -> Void
    ) async {
        if state == .listening {
            stop()
            return
        }
        guard state != .requestingPermission else { return }

        var authorization = recognizer.authorizationStatus()
        if authorization == .notDetermined {
            state = .requestingPermission
            let requestID = UUID()
            let requestTask = Task { await recognizer.requestAuthorization() }
            permissionRequestID = requestID
            permissionRequestTask = requestTask
            authorization = await withTaskCancellationHandler {
                await requestTask.value
            } onCancel: {
                requestTask.cancel()
            }
            guard permissionRequestID == requestID else { return }
            guard !requestTask.isCancelled else {
                permissionRequestID = nil
                permissionRequestTask = nil
                state = .idle
                return
            }
            permissionRequestID = nil
            permissionRequestTask = nil
        }

        switch authorization {
        case .authorized:
            start(currentText: currentText, onTextChange: onTextChange)
        case .denied, .restricted:
            state = .denied
        case .unavailable:
            state = .unavailable
        case .notDetermined:
            state = .failed("音声入力の権限状態を確認できませんでした")
        }
    }

    public func stop() {
        permissionRequestTask?.cancel()
        permissionRequestTask = nil
        permissionRequestID = nil
        do {
            try recognizer.stopRecognition()
            state = .idle
        } catch let error as DSVoiceInputError {
            state = .failed(error.message)
        } catch {
            state = .failed("録音を停止できませんでした: \(error.localizedDescription)")
        }
    }

    private func start(
        currentText: String,
        onTextChange: @escaping (String) -> Void
    ) {
        inputPrefix = currentText
        do {
            try recognizer.startRecognition(
                onTranscription: { [weak self] transcription in
                    guard let self else { return }
                    onTextChange(self.mergedText(transcription))
                },
                onFinish: { [weak self] in
                    self?.state = .idle
                },
                onError: { [weak self] error in
                    self?.state = .failed(error.message)
                }
            )
            state = .listening
        } catch let error as DSVoiceInputError {
            state = .failed(error.message)
        } catch {
            state = .failed("音声入力を開始できませんでした: \(error.localizedDescription)")
        }
    }

    private func mergedText(_ transcription: String) -> String {
        guard !inputPrefix.isEmpty else { return transcription }
        guard !transcription.isEmpty else { return inputPrefix }
        let separator = inputPrefix.last?.isWhitespace == true ? "" : " "
        return inputPrefix + separator + transcription
    }
}

#if os(iOS)
@available(iOS 17.0, *)
@MainActor
private final class DSLiveVoiceInputRecognizer: VoiceInputRecognizing {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var setupState = DSVoiceRecognitionSetupState()
    private var activeRecognitionID: UUID?

    func authorizationStatus() -> DSVoiceInputAuthorization {
        guard speechRecognizer?.isAvailable == true else { return .unavailable }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined: return .notDetermined
            case .denied: return .denied
            case .granted: return .authorized
            @unknown default: return .unavailable
            }
        @unknown default:
            return .unavailable
        }
    }

    func requestAuthorization() async -> DSVoiceInputAuthorization {
        let speechAuthorization: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speechAuthorization = await Self.requestSpeechAuthorization()
        } else {
            speechAuthorization = SFSpeechRecognizer.authorizationStatus()
        }

        switch speechAuthorization {
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        case .authorized: break
        @unknown default: return .unavailable
        }

        let microphoneGranted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneGranted = true
        case .denied:
            microphoneGranted = false
        case .undetermined:
            microphoneGranted = await Self.requestMicrophoneAuthorization()
        @unknown default:
            return .unavailable
        }
        return microphoneGranted ? .authorized : .denied
    }

    /// TCC の完了ブロックはメインキューを保証しない。@MainActor のクロージャを直接渡すと
    /// Swift 6 の実行時キュー検査で SIGTRAP になるため、非隔離境界で continuation を再開する。
    nonisolated private static func requestSpeechAuthorization()
        async -> SFSpeechRecognizerAuthorizationStatus
    {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization {
                continuation.resume(returning: $0)
            }
        }
    }

    nonisolated private static func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    func startRecognition(
        onTranscription: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (DSVoiceInputError) -> Void
    ) throws {
        guard authorizationStatus() == .authorized else {
            throw DSVoiceInputError.permissionDenied
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw DSVoiceInputError.unavailable
        }
        guard Self.supportsLiveAudioCapture else {
            // Simulator の CoreAudio は物理入力を持たず、AVAudioEngine.initialize が
            // RPC timeout でプロセスを abort する構成がある。危険 API の前で穏当に失敗させる。
            throw DSVoiceInputError.unavailable
        }
        guard !setupState.isStarting else {
            throw DSVoiceInputError.audioSessionFailed("音声入力は開始処理中です")
        }

        try stopRecognition()
        guard setupState.beginStart() else {
            throw DSVoiceInputError.audioSessionFailed("前回の録音資源を解放できませんでした")
        }
        defer { setupState.didFinishStart() }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 音声入力専用なので .record を使う。.default は入力経路を限定せず、
            // ミキシング用の .duckOthers も付けないことで、実機のルート変更に追従しやすくする。
            try audioSession.setCategory(.record, mode: .default, options: [])
            try audioSession.setActive(true)
            setupState.didActivateAudioSession()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            // setActive 後の inputFormat が実ハードウェア入力値。outputFormat は
            // セッション活性化で変化し得るため installTap には渡さない。
            let format = inputNode.inputFormat(forBus: 0)
            guard DSVoiceAudioFormatValidator.isValid(
                sampleRate: format.sampleRate,
                channelCount: format.channelCount,
                isStandard: format.isStandard
            ) else {
                throw DSVoiceInputError.unavailable
            }
            guard !setupState.hasInstalledAudioTap, !audioEngine.isRunning else {
                throw DSVoiceInputError.audioSessionFailed("録音エンジンが既に使用されています")
            }
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            setupState.didInstallAudioTap()

            audioEngine.prepare()
            try audioEngine.start()

            let recognitionID = UUID()
            activeRecognitionID = recognitionID
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcription = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let errorMessage = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.activeRecognitionID == recognitionID else { return }
                    if let transcription {
                        onTranscription(transcription)
                    }
                    if let errorMessage {
                        do {
                            try self.stopRecognition()
                        } catch {
                            onError(.audioSessionFailed(
                                "録音セッションを解放できませんでした: \(error.localizedDescription)"
                            ))
                            return
                        }
                        onError(.recognitionFailed("音声認識に失敗しました: \(errorMessage)"))
                    } else if isFinal {
                        do {
                            try self.stopRecognition()
                        } catch {
                            onError(.audioSessionFailed(
                                "録音セッションを解放できませんでした: \(error.localizedDescription)"
                            ))
                            return
                        }
                        onFinish()
                    }
                }
            }
        } catch {
            let startError: DSVoiceInputError
            if let voiceInputError = error as? DSVoiceInputError {
                startError = voiceInputError
            } else {
                startError = .audioSessionFailed(
                    "録音を開始できませんでした: \(error.localizedDescription)"
                )
            }
            do {
                try stopRecognition()
            } catch let cleanupError as DSVoiceInputError {
                throw cleanupError
            } catch {
                throw DSVoiceInputError.audioSessionFailed(
                    "録音セッションを解放できませんでした: \(error.localizedDescription)"
                )
            }
            throw startError
        }
    }

    func stopRecognition() throws {
        activeRecognitionID = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if setupState.hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            setupState.didRemoveAudioTap()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try deactivateAudioSession()
    }

    private func deactivateAudioSession() throws {
        guard setupState.isAudioSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            setupState.didDeactivateAudioSession()
        } catch {
            throw DSVoiceInputError.audioSessionFailed(
                "録音セッションを解放できませんでした: \(error.localizedDescription)"
            )
        }
    }

    nonisolated private static var supportsLiveAudioCapture: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}
#else
@MainActor
private final class DSLiveVoiceInputRecognizer: VoiceInputRecognizing {
    func authorizationStatus() -> DSVoiceInputAuthorization { .unavailable }
    func requestAuthorization() async -> DSVoiceInputAuthorization { .unavailable }
    func startRecognition(
        onTranscription: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (DSVoiceInputError) -> Void
    ) throws {
        throw DSVoiceInputError.unavailable
    }
    func stopRecognition() throws {}
}
#endif
