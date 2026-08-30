import CSQLite
import Foundation

@main
enum DaytonaOutcomePersistenceCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesu-daytona-outcome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("pesu.sqlite3")

        var legacyDatabase: OpaquePointer?
        precondition(sqlite3_open(databaseURL.path, &legacyDatabase) == SQLITE_OK)
        let legacySchema = """
            CREATE TABLE meetings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                started_at REAL NOT NULL,
                duration REAL NOT NULL,
                participants TEXT NOT NULL,
                summary TEXT NOT NULL,
                decisions TEXT NOT NULL,
                transcript TEXT NOT NULL,
                system_audio_path TEXT,
                microphone_path TEXT
            );
            """
        precondition(sqlite3_exec(legacyDatabase, legacySchema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(legacyDatabase)
        legacyDatabase = nil

        let store = try MeetingStore(databaseURL: databaseURL)
        let previewURL = URL(string: "https://example.daytona.app")!
        let artifactHTML = "<!doctype html><html><body>" + String(repeating: "Outcome", count: 90) + "</body></html>"
        let outcome = try DaytonaBuildOutcome(
            id: "6CB9419B-A5A4-44A4-9F3C-A1FB7CA1FF38",
            decisionID: "D1",
            action: "Build the approved landing page.",
            previewURL: previewURL,
            artifactHTML: artifactHTML,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let meeting = Meeting(
            id: 0,
            title: "Marketing catch-up",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 600,
            participants: [],
            summary: "The team approved a landing page.",
            decisions: [
                Decision(id: "D1", text: "Build the approved landing page.", evidenceSegmentID: "S1")
            ],
            transcript: [],
            systemAudioPath: "/tmp/system.caf",
            microphonePath: nil
        )
        let saved = try store.insert(meeting)
        try store.updateDaytonaOutcomes(forMeetingID: saved.id, outcomes: [outcome])

        let reloaded = try store.fetchMeetings().first!
        precondition(reloaded.daytonaOutcomes == [outcome])
        precondition(reloaded.daytonaOutcomes[0].previewURL == previewURL)
        precondition(reloaded.daytonaOutcomes[0].artifactHTML == artifactHTML)

        do {
            _ = try DaytonaBuildOutcome(
                decisionID: "D1",
                action: "Build it",
                previewURL: URL(string: "file:///tmp/index.html")!
            )
            preconditionFailure("A non-HTTPS preview URL must be rejected")
        } catch DaytonaBuildOutcome.ValidationError.invalidPreviewURL {
            // Expected.
        }

        print("Daytona meeting outcome migration and persistence checks passed")
    }
}
