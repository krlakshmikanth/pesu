import Foundation

enum CalendarFilterPolicy {
    static func isSuggestedDefaultOff(title: String, isBirthdayCalendar: Bool) -> Bool {
        if isBirthdayCalendar { return true }

        let normalized = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let lowValueCalendarNames = [
            "birthday",
            "birthdays",
            "holiday",
            "holidays",
            "daylight saving",
            "daylight savings"
        ]
        return lowValueCalendarNames.contains { normalized.contains($0) }
    }

    static func options(
        from sources: [CalendarSourceDescriptor],
        savedSelections: [String: Bool]
    ) -> [CalendarSourceOption] {
        sources.map { source in
            CalendarSourceOption(
                id: source.id,
                title: source.title,
                accountTitle: source.accountTitle,
                isSuggestedDefaultOff: source.isSuggestedDefaultOff,
                isEnabled: savedSelections[source.id] ?? !source.isSuggestedDefaultOff
            )
        }
    }
}
