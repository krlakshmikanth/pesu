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
