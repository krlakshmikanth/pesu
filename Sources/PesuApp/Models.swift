import Foundation

enum AppScreen: String, Equatable {
    case present
    case past
    case future
    case stats
    case settings
    case recording
    case summary
}

enum DuplicateMeetingScope: Equatable {
    case present
    case future
}

enum DuplicateResolutionStrategy: Equatable {
    case merge
    case keepOne
}

struct DuplicateResolutionResult {
    let groupsResolved: Int
    let copiesRemoved: Int
    let groupsSkipped: Int
}

struct CalendarSourceDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let accountTitle: String
    let isSuggestedDefaultOff: Bool
}

struct CalendarSourceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let accountTitle: String
    let isSuggestedDefaultOff: Bool
    var isEnabled: Bool
}

struct MicrophoneOption: Identifiable, Hashable, Sendable {
    static let systemDefaultID = "system-default"

    let id: String
    let name: String
    let detail: String
    let captureDeviceID: String?
}

struct LiveTranscriptSnapshot: Sendable {
    let finalizedSegments: [TranscriptSegment]
    let volatileText: String
    let status: String
}

struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let timestamp: String
    let speaker: String
    let text: String
}

struct Decision: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let text: String
    let evidenceSegmentID: String
}

struct DaytonaBuildOutcome: Codable, Hashable, Identifiable, Sendable {
    enum ValidationError: LocalizedError {
        case invalidPreviewURL
        case invalidArtifact
        case missingBuildRequest

        var errorDescription: String? {
            switch self {
            case .invalidPreviewURL:
                "Daytona did not return a safe HTTPS preview link."
            case .invalidArtifact:
                "Daytona did not return a valid HTML prototype."
            case .missingBuildRequest:
                "The completed Daytona build did not include an action."
            }
        }
    }

    let id: String
    let decisionID: String?
    let action: String
    let previewURL: URL
    let artifactHTML: String?
    let completedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case decisionID
        case action
        case previewURL
        case artifactHTML
        case completedAt
    }

    init(
        id: String = UUID().uuidString,
        decisionID: String?,
        action: String,
        previewURL: URL,
        artifactHTML: String? = nil,
        completedAt: Date = Date()
    ) throws {
        let cleanAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAction.isEmpty else { throw ValidationError.missingBuildRequest }
        guard previewURL.scheme?.lowercased() == "https", previewURL.host != nil else {
            throw ValidationError.invalidPreviewURL
        }
        if let artifactHTML {
            let artifactSize = artifactHTML.lengthOfBytes(using: .utf8)
            guard artifactSize >= 500, artifactSize <= 500_000 else {
                throw ValidationError.invalidArtifact
            }
        }
        self.id = id
        self.decisionID = decisionID
        self.action = String(cleanAction.prefix(1_000))
        self.previewURL = previewURL
        self.artifactHTML = artifactHTML
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(String.self, forKey: .id),
            decisionID: values.decodeIfPresent(String.self, forKey: .decisionID),
            action: values.decode(String.self, forKey: .action),
            previewURL: values.decode(URL.self, forKey: .previewURL),
            artifactHTML: values.decodeIfPresent(String.self, forKey: .artifactHTML),
            completedAt: values.decode(Date.self, forKey: .completedAt)
        )
    }

}

struct Meeting: Identifiable, Hashable {
    let id: Int64
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var participants: [String]
    var summary: String
    var decisions: [Decision]
    var transcript: [TranscriptSegment]
    var systemAudioPath: String?
    var microphonePath: String?
    var daytonaOutcomes: [DaytonaBuildOutcome] = []
    var isAllDay: Bool = false
    var calendarName: String? = nil

    static let empty = Meeting(
        id: 0,
        title: "",
        startedAt: .distantPast,
        duration: 0,
        participants: [],
        summary: "",
        decisions: [],
        transcript: [],
        systemAudioPath: nil,
        microphonePath: nil
    )
}

extension TimeInterval {
    var clockString: String {
        let total = max(0, Int(self))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var minuteString: String {
        "\(max(1, Int(self / 60))) min"
    }
}
