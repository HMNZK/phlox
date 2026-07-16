import Testing
@testable import DesignSystemIOS

@Suite struct DSVoiceInputControllerWave6Tests {
    @Test(arguments: [
        (48_000.0, UInt32(1)),
        (44_100.0, UInt32(2)),
    ])
    func validHardwareInputFormatCanInstallTap(
        sampleRate: Double,
        channelCount: UInt32
    ) {
        #expect(DSVoiceAudioFormatValidator.isValid(
            sampleRate: sampleRate,
            channelCount: channelCount
        ))
    }

    @Test(arguments: [
        (0.0, UInt32(1)),
        (-1.0, UInt32(1)),
        (Double.nan, UInt32(1)),
        (Double.infinity, UInt32(1)),
        (48_000.0, UInt32(0)),
    ])
    func invalidHardwareInputFormatIsRejectedBeforeInstallingTap(
        sampleRate: Double,
        channelCount: UInt32
    ) {
        #expect(!DSVoiceAudioFormatValidator.isValid(
            sampleRate: sampleRate,
            channelCount: channelCount
        ))
    }

    @Test func nonStandardPCMFormatIsRejectedBeforeInstallingTap() {
        #expect(!DSVoiceAudioFormatValidator.isValid(
            sampleRate: 48_000,
            channelCount: 1,
            isStandard: false
        ))
    }

    @Test func setupStateRejectsReentryUntilFailedStartResourcesAreReleased() {
        var state = DSVoiceRecognitionSetupState()

        let firstStart = state.beginStart()
        let reentrantStart = state.beginStart()
        #expect(firstStart)
        #expect(!reentrantStart)

        state.didActivateAudioSession()
        state.didInstallAudioTap()
        state.didFinishStart()

        #expect(state.requiresCleanup)
        let startWhileResourcesAreHeld = state.beginStart()
        #expect(!startWhileResourcesAreHeld)

        state.didRemoveAudioTap()
        state.didDeactivateAudioSession()

        #expect(!state.requiresCleanup)
        let startAfterCleanup = state.beginStart()
        #expect(startAfterCleanup)
    }
}
