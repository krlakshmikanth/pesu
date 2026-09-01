import Foundation

@main
enum PetPresentationCheck {
    static func main() {
        precondition(AppModelChange.content.requiresPageRender)
        precondition(!AppModelChange.petPresentation.requiresPageRender)

        let base = PetObservation(
            screen: .present,
            isRecording: false,
            hasLiveTranscript: false,
            hasSelectedMeeting: false,
            captureStatus: "Ready",
            speechStatus: "Live transcription ready",
            storeStatus: "Local database ready"
        )
        precondition(PetActivityMapper.activity(for: base) == .idle)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .recording, isRecording: true, captureStatus: "Preparing System Default…")) == .meetingStarting)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .recording, isRecording: true, captureStatus: "Recording locally", speechStatus: "Live transcription · on device")) == .listening)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .recording, isRecording: true, hasLiveTranscript: true, captureStatus: "Recording locally", speechStatus: "Live transcription · on device")) == .transcribing)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .recording, captureStatus: "Creating the summary on this Mac…", speechStatus: "Transcript finalized locally")) == .transcriptionComplete)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .recording, captureStatus: "Creating the summary on this Mac…")) == .summarizing)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .summary, hasSelectedMeeting: true)) == .complete)
        precondition(PetActivityMapper.activity(for: replacing(base, screen: .recording, captureStatus: "Recording could not start: denied")) == .error)

        let suiteName = "PetPresentationCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        precondition(PetPreferences.load(from: defaults) == PetPreferenceSnapshot(isEnabled: true, selectedPet: .corgi))
        PetPreferences.setEnabled(false, in: defaults)
        PetPreferences.setSelectedPet(.mrBean, in: defaults)
        precondition(PetPreferences.load(from: defaults) == PetPreferenceSnapshot(isEnabled: false, selectedPet: .mrBean))
        defaults.set("not-a-pet", forKey: PetPreferences.selectionKey)
        precondition(PetPreferences.load(from: defaults).selectedPet == .corgi)

        precondition(PetActivity.error.animation.row == 5)
        precondition(PetActivity.summarizing.animation.row == 8)
        precondition(PetActivity.transcriptionComplete.animation.frameCount == 5)
        print("Pet state mapping and preference checks passed")
    }

    private static func replacing(
        _ value: PetObservation,
        screen: AppScreen? = nil,
        isRecording: Bool? = nil,
        hasLiveTranscript: Bool? = nil,
        hasSelectedMeeting: Bool? = nil,
        captureStatus: String? = nil,
        speechStatus: String? = nil,
        storeStatus: String? = nil
    ) -> PetObservation {
        PetObservation(
            screen: screen ?? value.screen,
            isRecording: isRecording ?? value.isRecording,
            hasLiveTranscript: hasLiveTranscript ?? value.hasLiveTranscript,
            hasSelectedMeeting: hasSelectedMeeting ?? value.hasSelectedMeeting,
            captureStatus: captureStatus ?? value.captureStatus,
            speechStatus: speechStatus ?? value.speechStatus,
            storeStatus: storeStatus ?? value.storeStatus
        )
    }
}
