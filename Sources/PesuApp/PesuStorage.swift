import Foundation

enum PesuStorage {
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pēsu", isDirectory: true)
    }

    static var recordingsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    static var recordingsDirectoryPath: String {
        recordingsDirectory.path
    }

    static var displayRecordingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = recordingsDirectoryPath
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

enum RecordingPreferences {
    static let keepAudioFilesKey = "pesu.recording.keepAudioFiles"

    static func keepAudioFiles(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: keepAudioFilesKey) == nil
            ? true
            : defaults.bool(forKey: keepAudioFilesKey)
    }

    static func setKeepAudioFiles(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: keepAudioFilesKey)
    }
}

enum RecordingRetention {
    static func persistedAudioPaths(
        systemAudioPath: String?,
        microphonePath: String?,
        keepAudioFiles: Bool
    ) -> (systemAudioPath: String?, microphonePath: String?) {
        keepAudioFiles
            ? (systemAudioPath, microphonePath)
            : (nil, nil)
    }
}
