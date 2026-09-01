import Foundation

@main
enum PetPresentationCheck {
    static func main() {
        precondition(AppModelChange.content.requiresPageRender)
        precondition(!AppModelChange.petPresentation.requiresPageRender)
        precondition(!AppModelChange.process.requiresPageRender)

        let processMap: [(AppProcessPhase, PetActivity)] = [
            (.idle, .idle),
            (.meetingStarting, .meetingStarting),
            (.listening, .listening),
            (.transcribing, .transcribing),
            (.finalizingTranscription, .finalizingTranscription),
            (.transcriptionComplete, .transcriptionComplete),
            (.summarizing, .summarizing),
            (.summaryComplete, .summaryComplete),
            (.daytonaStarting, .daytonaStarting),
            (.daytonaWorking, .daytonaWorking),
            (.daytonaComplete, .daytonaComplete),
            (.error, .error)
        ]
        for (phase, expected) in processMap {
            precondition(PetActivityMapper.activity(for: phase) == expected)
        }

        precondition(PetActivity.meetingStarting.animation.row == 1)
        precondition(PetActivity.listening.animation.row == 6)
        precondition(PetActivity.transcribing.animation.row == 7)
        precondition(PetActivity.finalizingTranscription.animation.row == 8)
        precondition(PetActivity.transcriptionComplete.animation.row == 4)
        precondition(PetActivity.summarizing.animation.row == 8)
        precondition(PetActivity.summaryComplete.animation.row == 3)
        precondition(PetActivity.daytonaStarting.animation.row == 6)
        precondition(PetActivity.daytonaWorking.animation.row == 7)
        precondition(PetActivity.daytonaComplete.animation.row == 3)
        precondition(PetActivity.error.animation.row == 5)

        precondition(DaytonaWorkspaceEvent.EventType.preparing.appProcessPhase == .daytonaStarting)
        precondition(DaytonaWorkspaceEvent.EventType.creatingSandbox.appProcessPhase == .daytonaStarting)
        precondition(DaytonaWorkspaceEvent.EventType.runningAgent.appProcessPhase == .daytonaWorking)
        precondition(DaytonaWorkspaceEvent.EventType.activity.appProcessPhase == .daytonaWorking)
        precondition(DaytonaWorkspaceEvent.EventType.ready.appProcessPhase == .daytonaComplete)
        precondition(DaytonaWorkspaceEvent.EventType.failed.appProcessPhase == .error)

        for activity in [
            PetActivity.finalizingTranscription,
            .transcriptionComplete,
            .summarizing,
            .summaryComplete,
            .daytonaStarting,
            .daytonaComplete,
            .error
        ] {
            precondition(activity.minimumVisibleDuration > 0)
        }

        var meetingQueue = PetActivityQueue()
        precondition(meetingQueue.observe(.finalizingTranscription, whileHolding: false) == .finalizingTranscription)
        precondition(meetingQueue.observe(.transcriptionComplete, whileHolding: true) == nil)
        precondition(meetingQueue.observe(.summarizing, whileHolding: true) == nil)
        precondition(meetingQueue.observe(.summaryComplete, whileHolding: true) == nil)
        precondition(meetingQueue.advance() == .transcriptionComplete)
        precondition(meetingQueue.advance() == .summarizing)
        precondition(meetingQueue.advance() == .summaryComplete)
        precondition(meetingQueue.advance() == nil)

        var daytonaQueue = PetActivityQueue()
        precondition(daytonaQueue.observe(.daytonaStarting, whileHolding: false) == .daytonaStarting)
        precondition(daytonaQueue.observe(.daytonaWorking, whileHolding: true) == nil)
        precondition(daytonaQueue.observe(.daytonaComplete, whileHolding: true) == nil)
        precondition(daytonaQueue.advance() == .daytonaWorking)
        precondition(daytonaQueue.advance() == .daytonaComplete)

        let suiteName = "PetPresentationCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        precondition(PetPreferences.load(from: defaults) == PetPreferenceSnapshot(isEnabled: true, selectedPet: .corgi))
        PetPreferences.setEnabled(false, in: defaults)
        PetPreferences.setSelectedPet(.mrBean, in: defaults)
        precondition(PetPreferences.load(from: defaults) == PetPreferenceSnapshot(isEnabled: false, selectedPet: .mrBean))
        let expectedPets: [(PetChoice, String, String)] = [
            (.corgi, "looklookme", "Corgi"),
            (.mrBean, "mr-bean", "Mr Bean"),
            (.trump, "trump", "Trump"),
            (.pikachu, "pikachu-local", "Pikachu"),
            (.tom, "a-tom", "Tom"),
            (.goose, "theveller", "Goose")
        ]
        precondition(PetChoice.allCases.count == expectedPets.count)
        for (pet, resourceName, displayName) in expectedPets {
            precondition(pet.rawValue == resourceName)
            precondition(pet.displayName == displayName)
            PetPreferences.setSelectedPet(pet, in: defaults)
            precondition(PetPreferences.load(from: defaults).selectedPet == pet)
        }
        defaults.set("not-a-pet", forKey: PetPreferences.selectionKey)
        precondition(PetPreferences.load(from: defaults).selectedPet == .corgi)

        print("Pet process, Daytona event, animation visibility, and preference checks passed")
    }
}
