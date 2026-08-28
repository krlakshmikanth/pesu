import Foundation

struct DuplicateMeetingGroup: Identifiable {
    let key: String
    let meetings: [Meeting]

    var id: String { key }
    var copiesCount: Int { max(0, meetings.count - 1) }
}

enum MeetingDuplicateDetector {
    static func groups(in meetings: [Meeting]) -> [DuplicateMeetingGroup] {
        let calendarMeetings = meetings.filter { $0.calendarName != nil }
        let grouped = Dictionary(grouping: calendarMeetings, by: duplicateKey)

        return grouped
            .filter { $0.value.count > 1 }
            .map { key, values in
                DuplicateMeetingGroup(
                    key: key,
                    meetings: values.sorted {
                        if $0.calendarName == $1.calendarName { return $0.id < $1.id }
                        return ($0.calendarName ?? "") < ($1.calendarName ?? "")
                    }
                )
            }
            .sorted { lhs, rhs in
                (lhs.meetings.first?.startedAt ?? .distantFuture) < (rhs.meetings.first?.startedAt ?? .distantFuture)
            }
    }

    static func removingDuplicateCopies(from meetings: [Meeting]) -> [Meeting] {
        let duplicateIDs = Set(groups(in: meetings).flatMap { $0.meetings.dropFirst().map(\.id) })
        return meetings.filter { !duplicateIDs.contains($0.id) }
    }

    private static func duplicateKey(for meeting: Meeting) -> String {
        let normalizedTitle = meeting.title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        let startMinute = Int(meeting.startedAt.timeIntervalSince1970 / 60)
        let durationMinute = Int(meeting.duration / 60)
        return "\(normalizedTitle)|\(startMinute)|\(durationMinute)"
    }
}
