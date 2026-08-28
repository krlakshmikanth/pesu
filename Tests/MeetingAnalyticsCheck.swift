import Foundation

@main
enum MeetingAnalyticsCheck {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 8, 27, 15, 0, calendar: calendar)
        let firstStart = date(2026, 8, 26, 10, 0, calendar: calendar)
        let secondStart = date(2026, 8, 25, 9, 0, calendar: calendar)

        let first = meeting(id: 1, title: "Product Review", start: firstStart, duration: 3_600, calendar: "Work")
        let duplicate = meeting(id: 2, title: " product  review ", start: firstStart, duration: 3_600, calendar: "Personal")
        let second = meeting(id: 3, title: "Planning", start: secondStart, duration: 7_200, calendar: "Work")
        let nearButDifferent = meeting(id: 4, title: "Product Review", start: firstStart.addingTimeInterval(60), duration: 3_600, calendar: "Work")
        let future = meeting(id: 5, title: "Future", start: now.addingTimeInterval(3_600), duration: 3_600, calendar: "Work")

        let groups = MeetingDuplicateDetector.groups(in: [first, duplicate, second, nearButDifferent])
        precondition(groups.count == 1)
        precondition(groups[0].copiesCount == 1)
        precondition(Set(groups[0].meetings.map(\.id)) == Set([1, 2]))

        let stats = MeetingStatsSnapshot.calculate(
            from: [first, duplicate, second, future],
            now: now,
            calendar: calendar
        )
        precondition(stats.completedMeetings == 2)
        precondition(stats.meetingDays == 2)
        precondition(stats.totalDuration == 10_800)
        precondition(stats.averageDuration == 5_400)
        precondition(stats.busiestDay.duration == 7_200)
        precondition(stats.globalAverageLifetimeDays > 26_000)

        print("Duplicate detection and meeting statistics checks passed")
    }

    private static func meeting(
        id: Int64,
        title: String,
        start: Date,
        duration: TimeInterval,
        calendar: String
    ) -> Meeting {
        Meeting(
            id: id,
            title: title,
            startedAt: start,
            duration: duration,
            participants: [],
            summary: "",
            decisions: [],
            transcript: [],
            systemAudioPath: nil,
            microphonePath: nil,
            calendarName: calendar
        )
    }

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
