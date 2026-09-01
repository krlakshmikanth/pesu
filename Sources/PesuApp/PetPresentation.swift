import Foundation

enum AppModelChange: Equatable {
    case content
    case petPresentation
    case process

    var requiresPageRender: Bool { self == .content }
}

enum AppProcessPhase: String, CaseIterable, Equatable {
    case idle
    case meetingStarting
    case listening
    case transcribing
    case finalizingTranscription
    case transcriptionComplete
    case summarizing
    case summaryComplete
    case daytonaStarting
    case daytonaWorking
    case daytonaComplete
    case error
}

enum PetChoice: String, CaseIterable, Equatable {
    case corgi = "looklookme"
    case mrBean = "mr-bean"
    case trump
    case pikachu = "pikachu-local"
    case tom = "a-tom"
    case goose = "theveller"

    var displayName: String {
        switch self {
        case .corgi: "Corgi"
        case .mrBean: "Mr Bean"
        case .trump: "Trump"
        case .pikachu: "Pikachu"
        case .tom: "Tom"
        case .goose: "Goose"
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
    case playful
    case meetingStarting
    case listening
    case transcribing
    case finalizingTranscription
    case transcriptionComplete
    case summarizing
    case summaryComplete
    case daytonaStarting
    case daytonaWorking
    case daytonaComplete
    case error

    var displayName: String {
        switch self {
        case .idle: "Ready"
        case .playful: "Hello"
        case .meetingStarting: "Meeting starting"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .finalizingTranscription: "Finalizing transcript"
        case .transcriptionComplete: "Transcript complete"
        case .summarizing: "Summarizing"
        case .summaryComplete: "Summary complete"
        case .daytonaStarting: "Starting Daytona"
        case .daytonaWorking: "Daytona working"
        case .daytonaComplete: "Daytona complete"
        case .error: "Needs attention"
        }
    }

    var animation: PetAnimationSpec {
        switch self {
        case .idle: PetAnimationSpec(row: 0, frameCount: 6, frameDuration: 0.18)
        case .playful: PetAnimationSpec(row: 4, frameCount: 5, frameDuration: 0.14)
        case .meetingStarting: PetAnimationSpec(row: 1, frameCount: 8, frameDuration: 0.12)
        case .listening: PetAnimationSpec(row: 6, frameCount: 6, frameDuration: 0.15)
        case .transcribing: PetAnimationSpec(row: 7, frameCount: 6, frameDuration: 0.14)
        case .finalizingTranscription: PetAnimationSpec(row: 8, frameCount: 6, frameDuration: 0.15)
        case .transcriptionComplete: PetAnimationSpec(row: 4, frameCount: 5, frameDuration: 0.14)
        case .summarizing: PetAnimationSpec(row: 8, frameCount: 6, frameDuration: 0.15)
        case .summaryComplete: PetAnimationSpec(row: 3, frameCount: 4, frameDuration: 0.14)
        case .daytonaStarting: PetAnimationSpec(row: 6, frameCount: 6, frameDuration: 0.15)
        case .daytonaWorking: PetAnimationSpec(row: 7, frameCount: 6, frameDuration: 0.14)
        case .daytonaComplete: PetAnimationSpec(row: 3, frameCount: 4, frameDuration: 0.14)
        case .error: PetAnimationSpec(row: 5, frameCount: 8, frameDuration: 0.14)
        }
    }

    var minimumVisibleDuration: TimeInterval {
        switch self {
        case .meetingStarting, .finalizingTranscription, .summarizing, .daytonaStarting:
            0.55
        case .transcriptionComplete, .summaryComplete, .daytonaComplete, .error:
            0.9
        case .idle, .playful, .listening, .transcribing, .daytonaWorking:
            0
        }
    }
}

struct PetAnimationSpec: Equatable {
    let row: Int
    let frameCount: Int
    let frameDuration: TimeInterval
}

struct PetActivityQueue: Equatable {
    private(set) var current: PetActivity = .idle
    private(set) var pending: [PetActivity] = []
    private var lastObserved: PetActivity?

    mutating func observe(_ activity: PetActivity, whileHolding: Bool) -> PetActivity? {
        guard activity != lastObserved else { return nil }
        lastObserved = activity
        if whileHolding {
            if pending.last != activity { pending.append(activity) }
            return nil
        }
        current = activity
        return activity
    }

    mutating func advance() -> PetActivity? {
        guard !pending.isEmpty else { return nil }
        current = pending.removeFirst()
        return current
    }
}

enum PetActivityMapper {
    static func activity(for phase: AppProcessPhase) -> PetActivity {
        switch phase {
        case .idle: .idle
        case .meetingStarting: .meetingStarting
        case .listening: .listening
        case .transcribing: .transcribing
        case .finalizingTranscription: .finalizingTranscription
        case .transcriptionComplete: .transcriptionComplete
        case .summarizing: .summarizing
        case .summaryComplete: .summaryComplete
        case .daytonaStarting: .daytonaStarting
        case .daytonaWorking: .daytonaWorking
        case .daytonaComplete: .daytonaComplete
        case .error: .error
        }
    }
}
