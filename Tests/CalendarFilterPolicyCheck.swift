import Foundation

@main
enum CalendarFilterPolicyCheck {
    static func main() {
        precondition(CalendarFilterPolicy.isSuggestedDefaultOff(title: "Birthdays", isBirthdayCalendar: false))
        precondition(CalendarFilterPolicy.isSuggestedDefaultOff(title: "Holidays in the United Kingdom", isBirthdayCalendar: false))
        precondition(CalendarFilterPolicy.isSuggestedDefaultOff(title: "Daylight Saving Time", isBirthdayCalendar: false))
        precondition(CalendarFilterPolicy.isSuggestedDefaultOff(title: "Contacts", isBirthdayCalendar: true))
        precondition(!CalendarFilterPolicy.isSuggestedDefaultOff(title: "Work", isBirthdayCalendar: false))
        precondition(!CalendarFilterPolicy.isSuggestedDefaultOff(title: "Personal", isBirthdayCalendar: false))

        let sources = [
            CalendarSourceDescriptor(id: "work", title: "Work", accountTitle: "iCloud", isSuggestedDefaultOff: false),
            CalendarSourceDescriptor(id: "holidays", title: "UK Holidays", accountTitle: "Other", isSuggestedDefaultOff: true)
        ]
        let defaults = CalendarFilterPolicy.options(from: sources, savedSelections: [:])
        precondition(defaults.first(where: { $0.id == "work" })?.isEnabled == true)
        precondition(defaults.first(where: { $0.id == "holidays" })?.isEnabled == false)

        let explicitChoice = CalendarFilterPolicy.options(from: sources, savedSelections: ["holidays": true])
        precondition(explicitChoice.first(where: { $0.id == "holidays" })?.isEnabled == true)
        print("Calendar source default checks passed")
    }
}
