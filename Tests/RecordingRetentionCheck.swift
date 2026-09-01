import Foundation

@main
enum RecordingRetentionCheck {
    static func main() {
        let suiteName = "RecordingRetentionCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        precondition(RecordingPreferences.keepAudioFiles(from: defaults))
        RecordingPreferences.setKeepAudioFiles(false, in: defaults)
        precondition(!RecordingPreferences.keepAudioFiles(from: defaults))
        RecordingPreferences.setKeepAudioFiles(true, in: defaults)
        precondition(RecordingPreferences.keepAudioFiles(from: defaults))

        let kept = RecordingRetention.persistedAudioPaths(
            systemAudioPath: "/tmp/system.m4a",
            microphonePath: "/tmp/mic.m4a",
            keepAudioFiles: true
        )
        precondition(kept.systemAudioPath == "/tmp/system.m4a")
        precondition(kept.microphonePath == "/tmp/mic.m4a")

        let discarded = RecordingRetention.persistedAudioPaths(
            systemAudioPath: "/tmp/system.m4a",
            microphonePath: "/tmp/mic.m4a",
            keepAudioFiles: false
        )
        precondition(discarded.systemAudioPath == nil)
        precondition(discarded.microphonePath == nil)

        let missing = RecordingRetention.persistedAudioPaths(
            systemAudioPath: nil,
            microphonePath: nil,
            keepAudioFiles: true
        )
        precondition(missing.systemAudioPath == nil)
        precondition(missing.microphonePath == nil)

        precondition(PesuStorage.recordingsDirectory.lastPathComponent == "Recordings")
        precondition(PesuStorage.recordingsDirectory.deletingLastPathComponent().lastPathComponent == "Pēsu")
        precondition(PesuStorage.displayRecordingsPath.contains("Pēsu/Recordings"))

        print("Recording retention and storage path checks passed")
    }
}
