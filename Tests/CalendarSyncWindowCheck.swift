import Foundation

@main
struct CalendarSyncWindowCheck {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = DateComponents(calendar: calendar, year: 2026, month: 8, day: 27, hour: 15).date!

        let pastStart = CalendarSyncWindow.pastStart(relativeTo: reference, calendar: calendar)
        precondition(calendar.dateComponents([.year, .month, .day], from: pastStart) == DateComponents(year: 2025, month: 8, day: 27))

        let initial = CalendarSyncWindow.initialFutureEnd(relativeTo: reference, calendar: calendar)
        precondition(calendar.dateComponents([.year, .month, .day], from: initial) == DateComponents(year: 2030, month: 8, day: 27))

        let extended = (0..<20).reduce(initial) { end, _ in CalendarSyncWindow.extending(end, calendar: calendar) }
        precondition(calendar.component(.year, from: extended) == 2110)
        print("Calendar sync window checks passed")
    }
}
