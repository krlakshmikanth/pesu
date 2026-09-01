import Foundation

enum AppModelChange: Equatable {
    case content
    case petPresentation

    var requiresPageRender: Bool { self == .content }
}

enum PetChoice: String, CaseIterable, Equatable {
    case corgi = "looklookme"
    case mrBean = "mr-bean"
    case trump

    var displayName: String {
        switch self {
        case .corgi: "Corgi"
        case .mrBean: "Mr Bean"
        case .trump: "Trump"
        }
    }
}

struct PetPreferenceSnapshot: Equatable {
    let isEnabled: Bool
    let selectedPet: PetChoice
}

enum PetPreferences {
    static let enabledKey = "pesu.pets.enabled"
    static let selectionKey = "pesu.pets.selection"

    static func load(from defaults: UserDefaults = .standard) -> PetPreferenceSnapshot {
        let isEnabled = defaults.object(forKey: enabledKey) == nil
            ? true
            : defaults.bool(forKey: enabledKey)
        let selectedPet = defaults.string(forKey: selectionKey)
            .flatMap(PetChoice.init(rawValue:)) ?? .corgi
        return PetPreferenceSnapshot(isEnabled: isEnabled, selectedPet: selectedPet)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func setSelectedPet(_ pet: PetChoice, in defaults: UserDefaults = .standard) {
        defaults.set(pet.rawValue, forKey: selectionKey)
    }
}

enum PetActivity: String, CaseIterable, Equatable {
    case idle
    case meetingStarting
    case listening
    case transcribing
    case transcriptionComplete
    case summarizing
    case complete
    case error

    var displayName: String {
        switch self {
        case .idle: "Ready"
        case .meetingStarting: "Meeting starting"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .transcriptionComplete: "Transcript complete"
        case .summarizing: "Summarizing"
        case .complete: "Complete"
        case .error: "Needs attention"
        }
    }

    var animation: PetAnimationSpec {
        switch self {
        case .idle: PetAnimationSpec(row: 0, frameCount: 6, frameDuration: 0.18)
        case .meetingStarting: PetAnimationSpec(row: 1, frameCount: 8, frameDuration: 0.12)
        case .listening: PetAnimationSpec(row: 6, frameCount: 6, frameDuration: 0.15)
        case .transcribing: PetAnimationSpec(row: 7, frameCount: 6, frameDuration: 0.14)
        case .transcriptionComplete: PetAnimationSpec(row: 4, frameCount: 5, frameDuration: 0.14)
        case .summarizing: PetAnimationSpec(row: 8, frameCount: 6, frameDuration: 0.15)
        case .complete: PetAnimationSpec(row: 3, frameCount: 4, frameDuration: 0.14)
        case .error: PetAnimationSpec(row: 5, frameCount: 8, frameDuration: 0.14)
        }
    }
}

struct PetAnimationSpec: Equatable {
    let row: Int
    let frameCount: Int
    let frameDuration: TimeInterval
}

struct PetObservation: Equatable {
    let screen: AppScreen
    let isRecording: Bool
    let hasLiveTranscript: Bool
    let hasSelectedMeeting: Bool
    let captureStatus: String
    let speechStatus: String
    let storeStatus: String
}

enum PetActivityMapper {
    static func activity(for observation: PetObservation) -> PetActivity {
        if containsError(observation.captureStatus)
            || containsError(observation.speechStatus)
            || containsError(observation.storeStatus) {
            return .error
        }

        guard observation.screen == .recording else {
            return observation.screen == .summary && observation.hasSelectedMeeting ? .complete : .idle
        }

        if observation.isRecording {
            let preparationCopy = [observation.captureStatus, observation.speechStatus]
                .joined(separator: " ")
                .lowercased()
            if preparationCopy.contains("preparing") || preparationCopy.contains("downloading") {
                return .meetingStarting
            }
            return observation.hasLiveTranscript ? .transcribing : .listening
        }

        let speechStatus = observation.speechStatus.lowercased()
        if speechStatus.contains("transcript finalized") || speechStatus.contains("no speech detected") {
            return .transcriptionComplete
        }

        if observation.captureStatus.lowercased().contains("summary") {
            return .summarizing
        }

        return .idle
    }

    private static func containsError(_ status: String) -> Bool {
        let status = status.lowercased()
        return status.contains("could not")
            || status.contains("unavailable:")
            || status.contains("save failed")
            || status.contains("database unavailable")
            || status.contains("transcription stopped:")
    }
}
