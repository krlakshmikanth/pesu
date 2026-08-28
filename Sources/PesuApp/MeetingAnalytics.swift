import Foundation

struct MeetingPeriodHighlight {
    let label: String
    let duration: TimeInterval

    static let empty = MeetingPeriodHighlight(label: "No meetings yet", duration: 0)
}

struct MeetingStatsSnapshot {
    static let globalAverageLifeExpectancyYears = 73.3

    let completedMeetings: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let meetingDays: Int
    let dailyDurations: [Date: TimeInterval]
    let busiestDay: MeetingPeriodHighlight
    let busiestWeek: MeetingPeriodHighlight
    let busiestMonth: MeetingPeriodHighlight
    let rangeStart: Date
    let rangeEnd: Date

    var globalAverageLifetimeDays: Int {
        Int((Self.globalAverageLifeExpectancyYears * 365.2425).rounded())
    }

    static func calculate(
        from meetings: [Meeting],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MeetingStatsSnapshot {
        let rangeEnd = now
        let rangeStart = calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let completed = MeetingDuplicateDetector.removingDuplicateCopies(from: meetings)
            .filter {
                !$0.isAllDay &&
                $0.startedAt >= rangeStart &&
                $0.startedAt.addingTimeInterval($0.duration) <= now
            }

        let totalDuration = completed.reduce(0) { $0 + $1.duration }
        let dailyDurations = Dictionary(grouping: completed) { calendar.startOfDay(for: $0.startedAt) }
            .mapValues { $0.reduce(0) { $0 + $1.duration } }

        let weeklyDurations = Dictionary(grouping: completed) {
            calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? calendar.startOfDay(for: $0.startedAt)
        }.mapValues { $0.reduce(0) { $0 + $1.duration } }

        let monthlyDurations = Dictionary(grouping: completed) {
            calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? calendar.startOfDay(for: $0.startedAt)
        }.mapValues { $0.reduce(0) { $0 + $1.duration } }

        let busiestDay = highlight(in: dailyDurations) { date in
            date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
        let busiestWeek = highlight(in: weeklyDurations) { date in
            let end = calendar.date(byAdding: .day, value: 6, to: date) ?? date
            return "\(date.formatted(.dateTime.day().month(.abbreviated)))–\(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
        let busiestMonth = highlight(in: monthlyDurations) { date in
            date.formatted(.dateTime.month(.wide).year())
        }

        return MeetingStatsSnapshot(
            completedMeetings: completed.count,
            totalDuration: totalDuration,
            averageDuration: completed.isEmpty ? 0 : totalDuration / Double(completed.count),
            meetingDays: dailyDurations.count,
            dailyDurations: dailyDurations,
            busiestDay: busiestDay,
            busiestWeek: busiestWeek,
            busiestMonth: busiestMonth,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
    }

    private static func highlight(
        in durations: [Date: TimeInterval],
        label: (Date) -> String
    ) -> MeetingPeriodHighlight {
        guard let busiest = durations.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }) else { return .empty }
        return MeetingPeriodHighlight(label: label(busiest.key), duration: busiest.value)
    }
}
