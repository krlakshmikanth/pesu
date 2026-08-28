import Foundation

enum CalendarSyncWindow {
    static func pastStart(relativeTo today: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: today)) ?? today
    }

    static func initialFutureEnd(relativeTo today: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: 4, to: calendar.startOfDay(for: today)) ?? today
    }

    static func extending(_ currentEnd: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: 4, to: currentEnd) ?? currentEnd
    }
}
