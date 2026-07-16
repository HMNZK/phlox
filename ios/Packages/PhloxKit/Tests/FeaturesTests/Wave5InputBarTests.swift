import Testing
@testable import Features

@MainActor
@Suite struct Wave5InputBarTests {
    @Test func authorizedRecognizerStartsAndWritesRecognizedText() async {
        let recognizer = VoiceInputRecognizerDouble(authorization: .authorized)
        let controller = DSVoiceInputController(recognizer: recognizer)
        var inputText = "既存"

        await controller.toggle(currentText: inputText) { inputText = $0 }
        recognizer.emit("音声入力")

        #expect(controller.state == .listening)
        #expect(recognizer.startCallCount == 1)
        #expect(inputText == "既存 音声入力")
    }

    @Test func undeterminedAuthorizationIsRequestedBeforeStarting() async {
        let recognizer = VoiceInputRecognizerDouble(
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )
        let controller = DSVoiceInputController(recognizer: recognizer)

        await controller.toggle(currentText: "") { _ in }

        #expect(recognizer.requestCallCount == 1)
        #expect(recognizer.startCallCount == 1)
        #expect(controller.state == .listening)
    }

    @Test(arguments: [
        DSVoiceInputAuthorization.denied,
        DSVoiceInputAuthorization.restricted,
    ])
    func deniedAuthorizationDoesNotStart(authorization: DSVoiceInputAuthorization) async {
        let recognizer = VoiceInputRecognizerDouble(authorization: authorization)
        let controller = DSVoiceInputController(recognizer: recognizer)

        await controller.toggle(currentText: "") { _ in }

        #expect(controller.state == .denied)
        #expect(recognizer.startCallCount == 0)
    }

    @Test func unavailableRecognizerFallsBackWithoutStarting() async {
        let recognizer = VoiceInputRecognizerDouble(authorization: .unavailable)
        let controller = DSVoiceInputController(recognizer: recognizer)

        await controller.toggle(currentText: "") { _ in }

        #expect(controller.state == .unavailable)
        #expect(recognizer.startCallCount == 0)
    }

    @Test func tappingWhileListeningStopsAndReturnsToIdle() async {
        let recognizer = VoiceInputRecognizerDouble(authorization: .authorized)
        let controller = DSVoiceInputController(recognizer: recognizer)

        await controller.toggle(currentText: "") { _ in }
        await controller.toggle(currentText: "") { _ in }

        #expect(controller.state == .idle)
        #expect(recognizer.stopCallCount == 1)
    }

    @Test func recognitionFailureIsRetainedAsAVisibleState() async {
        let recognizer = VoiceInputRecognizerDouble(authorization: .authorized)
        let controller = DSVoiceInputController(recognizer: recognizer)

        await controller.toggle(currentText: "") { _ in }
        recognizer.fail(.recognitionFailed("認識に失敗しました"))

        #expect(controller.state == .failed("認識に失敗しました"))
    }

    @Test func concurrentTogglesDuringPermissionRequestDoNotDoubleStart() async {
        let recognizer = SlowAuthorizationRecognizerDouble(
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )
        let controller = DSVoiceInputController(recognizer: recognizer)

        async let first: Void = controller.toggle(currentText: "") { _ in }
        async let second: Void = controller.toggle(currentText: "") { _ in }
        _ = await (first, second)

        #expect(recognizer.requestCallCount == 1)
        #expect(recognizer.startCallCount == 1)
    }

    @Test func micDoesNotStartAfterScreenDismissedWhilePermissionPending() async {
        let recognizer = PermissionGatedRecognizerDouble(
            authorization: .notDetermined,
            requestedAuthorization: .authorized
        )
        let controller = DSVoiceInputController(recognizer: recognizer)

        let toggleTask = Task { await controller.toggle(currentText: "") { _ in } }
        while !recognizer.hasPendingRequest {
            await Task.yield()
        }

        controller.stop()
        #expect(controller.state == .idle)

        recognizer.resolvePendingPermission()
        await toggleTask.value

        #expect(controller.state == .idle)
        #expect(recognizer.startCallCount == 0)
    }
}

@MainActor
private final class SlowAuthorizationRecognizerDouble: VoiceInputRecognizing {
    private var authorization: DSVoiceInputAuthorization
    private let requestedAuthorization: DSVoiceInputAuthorization
    private(set) var requestCallCount = 0
    private(set) var startCallCount = 0

    init(
        authorization: DSVoiceInputAuthorization,
        requestedAuthorization: DSVoiceInputAuthorization
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
    }

    func authorizationStatus() -> DSVoiceInputAuthorization { authorization }

    func requestAuthorization() async -> DSVoiceInputAuthorization {
        requestCallCount += 1
        await Task.yield()
        await Task.yield()
        authorization = requestedAuthorization
        return authorization
    }

    func startRecognition(
        onTranscription: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (DSVoiceInputError) -> Void
    ) throws {
        startCallCount += 1
    }

    func stopRecognition() throws {}
}

@MainActor
private final class PermissionGatedRecognizerDouble: VoiceInputRecognizing {
    private var authorization: DSVoiceInputAuthorization
    private let requestedAuthorization: DSVoiceInputAuthorization
    private var pending: CheckedContinuation<DSVoiceInputAuthorization, Never>?
    private(set) var startCallCount = 0
    var hasPendingRequest: Bool { pending != nil }

    init(
        authorization: DSVoiceInputAuthorization,
        requestedAuthorization: DSVoiceInputAuthorization
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
    }

    func authorizationStatus() -> DSVoiceInputAuthorization { authorization }

    func requestAuthorization() async -> DSVoiceInputAuthorization {
        await withCheckedContinuation { pending = $0 }
    }

    func resolvePendingPermission() {
        authorization = requestedAuthorization
        pending?.resume(returning: requestedAuthorization)
        pending = nil
    }

    func startRecognition(
        onTranscription: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (DSVoiceInputError) -> Void
    ) throws {
        startCallCount += 1
    }

    func stopRecognition() throws {}
}

@MainActor
private final class VoiceInputRecognizerDouble: VoiceInputRecognizing {
    private var authorization: DSVoiceInputAuthorization
    private let requestedAuthorization: DSVoiceInputAuthorization
    private var onTranscription: ((String) -> Void)?
    private var onError: ((DSVoiceInputError) -> Void)?

    private(set) var requestCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    init(
        authorization: DSVoiceInputAuthorization,
        requestedAuthorization: DSVoiceInputAuthorization? = nil
    ) {
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization ?? authorization
    }

    func authorizationStatus() -> DSVoiceInputAuthorization { authorization }

    func requestAuthorization() async -> DSVoiceInputAuthorization {
        requestCallCount += 1
        authorization = requestedAuthorization
        return authorization
    }

    func startRecognition(
        onTranscription: @escaping (String) -> Void,
        onFinish: @escaping () -> Void,
        onError: @escaping (DSVoiceInputError) -> Void
    ) throws {
        startCallCount += 1
        self.onTranscription = onTranscription
        self.onError = onError
    }

    func stopRecognition() throws {
        stopCallCount += 1
    }

    func emit(_ text: String) {
        onTranscription?(text)
    }

    func fail(_ error: DSVoiceInputError) {
        onError?(error)
    }
}
