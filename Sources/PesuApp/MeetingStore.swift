import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class MeetingStore {
    enum StoreError: LocalizedError {
        case open(String)
        case statement(String)

        var errorDescription: String? {
            switch self {
            case .open(let message), .statement(let message): message
            }
        }
    }

    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        let directory = PesuStorage.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("pesu.sqlite3").path

        guard sqlite3_open(path, &database) == SQLITE_OK else {
            throw StoreError.open("Could not open the local Pēsu database.")
        }

        try execute("""
            CREATE TABLE IF NOT EXISTS meetings (
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
            """)

        try removePrototypeMeetings()
    }

    deinit {
        sqlite3_close(database)
    }

    func fetchMeetings() throws -> [Meeting] {
        let sql = """
            SELECT id, title, started_at, duration, participants, summary,
                   decisions, transcript, system_audio_path, microphone_path
            FROM meetings ORDER BY started_at DESC;
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statement(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var meetings: [Meeting] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            meetings.append(try decodeMeeting(statement))
        }
        return meetings
    }

    @discardableResult
    func insert(_ meeting: Meeting) throws -> Meeting {
        let sql = """
            INSERT INTO meetings
            (title, started_at, duration, participants, summary, decisions, transcript, system_audio_path, microphone_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statement(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(meeting.title, at: 1, in: statement)
        sqlite3_bind_double(statement, 2, meeting.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, meeting.duration)
        bind(try json(meeting.participants), at: 4, in: statement)
        bind(meeting.summary, at: 5, in: statement)
        bind(try json(meeting.decisions), at: 6, in: statement)
        bind(try json(meeting.transcript), at: 7, in: statement)
        bindOptional(meeting.systemAudioPath, at: 8, in: statement)
        bindOptional(meeting.microphonePath, at: 9, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.statement(errorMessage)
        }

        var saved = meeting
        saved = Meeting(
            id: sqlite3_last_insert_rowid(database),
            title: saved.title,
            startedAt: saved.startedAt,
            duration: saved.duration,
            participants: saved.participants,
            summary: saved.summary,
            decisions: saved.decisions,
            transcript: saved.transcript,
            systemAudioPath: saved.systemAudioPath,
            microphonePath: saved.microphonePath
        )
        return saved
    }

    func updateTitle(forMeetingID id: Int64, to title: String) throws {
        let sql = "UPDATE meetings SET title = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statement(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(title, at: 1, in: statement)
        sqlite3_bind_int64(statement, 2, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.statement(errorMessage)
        }
    }

    func updateNotes(forMeetingID id: Int64, summary: String, decisions: [Decision]) throws {
        let sql = "UPDATE meetings SET summary = ?, decisions = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statement(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(summary, at: 1, in: statement)
        bind(try json(decisions), at: 2, in: statement)
        sqlite3_bind_int64(statement, 3, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.statement(errorMessage)
        }
    }

    func deleteMeeting(withID id: Int64) throws {
        let sql = "DELETE FROM meetings WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.statement(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.statement(errorMessage)
        }
    }

    private func removePrototypeMeetings() throws {
        try execute("""
            DELETE FROM meetings
            WHERE (title = 'Product review' AND summary LIKE 'The team chose a focused private alpha:%')
               OR (title = 'Weekly planning' AND summary = 'The next milestone was agreed with six follow-up actions.')
               OR (title = 'Research interview — Maya' AND summary = 'Customer language and onboarding friction were the main themes.')
               OR (title = 'Product planning' AND summary = 'Scheduled product planning conversation.')
               OR (title = 'Research follow-up' AND summary = 'Scheduled follow-up on the latest research findings.');
            """)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw StoreError.statement(message)
        }
    }

    private func decodeMeeting(_ statement: OpaquePointer?) throws -> Meeting {
        Meeting(
            id: sqlite3_column_int64(statement, 0),
            title: text(statement, 1),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            duration: sqlite3_column_double(statement, 3),
            participants: try decode([String].self, from: text(statement, 4)),
            summary: text(statement, 5),
            decisions: try decode([Decision].self, from: text(statement, 6)),
            transcript: try decode([TranscriptSegment].self, from: text(statement, 7)),
            systemAudioPath: optionalText(statement, 8),
            microphonePath: optionalText(statement, 9)
        )
    }

    private var errorMessage: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bindOptional(_ value: String?, at index: Int32, in statement: OpaquePointer?) {
        if let value { bind(value, at: index, in: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: String) throws -> T {
        try decoder.decode(type, from: Data(value.utf8))
    }
}
