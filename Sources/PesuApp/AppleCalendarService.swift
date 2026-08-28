import EventKit
import Foundation

actor AppleCalendarService {
    enum ConnectionState: Equatable {
        case notConnected
        case connected
        case denied

        var title: String {
            switch self {
            case .notConnected: "Not connected"
            case .connected: "Connected"
            case .denied: "Calendar access is off"
            }
        }
    }

    private let eventStore = EKEventStore()
    private var cachedEvents: [Int64: EKEvent] = [:]

    nonisolated var connectionState: ConnectionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .connected
        case .denied, .restricted, .writeOnly: .denied
        case .notDetermined: .notConnected
        @unknown default: .notConnected
        }
    }

    func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func calendarSources() -> [CalendarSourceDescriptor] {
        guard connectionState == .connected else { return [] }
        return eventStore.calendars(for: .event)
            .map { calendar in
                CalendarSourceDescriptor(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    accountTitle: calendar.source.title.nonEmpty ?? "On My Mac",
                    isSuggestedDefaultOff: CalendarFilterPolicy.isSuggestedDefaultOff(
                        title: calendar.title,
                        isBirthdayCalendar: calendar.type == .birthday
                    )
                )
            }
            .sorted {
                if $0.accountTitle == $1.accountTitle { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return $0.accountTitle.localizedCaseInsensitiveCompare($1.accountTitle) == .orderedAscending
            }
    }

    func fetchMeetings(
        from startDate: Date,
        to endDate: Date,
        calendarIdentifiers: Set<String>
    ) -> [Meeting] {
        guard connectionState == .connected, startDate < endDate else { return [] }
        let includedCalendars = eventStore.calendars(for: .event)
            .filter { calendarIdentifiers.contains($0.calendarIdentifier) }
        guard !includedCalendars.isEmpty else { return [] }

        let calendar = Calendar.current
        var cursor = startDate
        var eventsByOccurrence: [String: EKEvent] = [:]

        while cursor < endDate {
            let next = min(calendar.date(byAdding: .year, value: 4, to: cursor) ?? endDate, endDate)
            let predicate = eventStore.predicateForEvents(withStart: cursor, end: next, calendars: includedCalendars)
            for event in eventStore.events(matching: predicate) {
                let key = "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
                eventsByOccurrence[key] = event
            }
            cursor = next
        }

        let meetings = eventsByOccurrence.map { key, event in
            let meeting = meeting(from: event, occurrenceKey: key)
            cachedEvents[meeting.id] = event
            return meeting
        }
        return meetings.sorted { $0.startedAt < $1.startedAt }
    }

    func resolveDuplicateGroups(
        _ groups: [[Int64]],
        strategy: DuplicateResolutionStrategy
    ) -> DuplicateResolutionResult {
        guard connectionState == .connected else {
            return DuplicateResolutionResult(groupsResolved: 0, copiesRemoved: 0, groupsSkipped: groups.count)
        }

        var groupsResolved = 0
        var copiesRemoved = 0
        var groupsSkipped = 0

        for (groupIndex, ids) in groups.enumerated() {
            let events = ids.compactMap { cachedEvents[$0] }
            guard events.count == ids.count, events.count > 1 else {
                groupsSkipped += 1
                continue
            }

            let readOnlyEvents = events.filter { !$0.calendar.allowsContentModifications }
            let keeper: EKEvent
            if strategy == .keepOne, readOnlyEvents.count == 1 {
                keeper = readOnlyEvents[0]
            } else if readOnlyEvents.isEmpty {
                keeper = events.max(by: { metadataScore(for: $0) < metadataScore(for: $1) }) ?? events[0]
            } else {
                groupsSkipped += 1
                continue
            }

            let copies = events.filter { $0 !== keeper }
            guard copies.allSatisfy({ $0.calendar.allowsContentModifications }) else {
                groupsSkipped += 1
                continue
            }

            do {
                if strategy == .merge {
                    merge(events, into: keeper)
                    try eventStore.save(keeper, span: .thisEvent, commit: false)
                }
                for copy in copies {
                    try eventStore.remove(copy, span: .thisEvent, commit: false)
                }
                try eventStore.commit()
                copies.forEach { event in
                    cachedEvents = cachedEvents.filter { $0.value !== event }
                }
                groupsResolved += 1
                copiesRemoved += copies.count
            } catch {
                eventStore.reset()
                cachedEvents.removeAll()
                groupsSkipped += groups.count - groupIndex
                break
            }
        }

        return DuplicateResolutionResult(
            groupsResolved: groupsResolved,
            copiesRemoved: copiesRemoved,
            groupsSkipped: groupsSkipped
        )
    }

    private func meeting(from event: EKEvent, occurrenceKey: String) -> Meeting {
        let participants = event.attendees?.compactMap(\.name) ?? []
        let duration = max(event.endDate.timeIntervalSince(event.startDate), 60)
        let context = [event.calendar.title, event.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return Meeting(
            id: stableIdentifier(for: occurrenceKey),
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled calendar event",
            startedAt: event.startDate,
            duration: duration,
            participants: participants,
            summary: context.isEmpty ? "Apple Calendar" : context,
            decisions: [],
            transcript: [],
            systemAudioPath: nil,
            microphonePath: nil,
            isAllDay: event.isAllDay,
            calendarName: event.calendar.title
        )
    }

    private func stableIdentifier(for value: String) -> Int64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int64(bitPattern: hash | (1 << 63))
    }

    private func metadataScore(for event: EKEvent) -> Int {
        var score = 0
        if event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 4 }
        if event.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 2 }
        if event.url != nil { score += 2 }
        score += event.attendees?.count ?? 0
        return score
    }

    private func merge(_ events: [EKEvent], into keeper: EKEvent) {
        keeper.startDate = events.compactMap(\.startDate).min() ?? keeper.startDate
        keeper.endDate = events.compactMap(\.endDate).max() ?? keeper.endDate

        let notes = uniqueNonEmpty(events.compactMap(\.notes))
        if !notes.isEmpty { keeper.notes = notes.joined(separator: "\n\n—\n\n") }

        if keeper.location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            keeper.location = uniqueNonEmpty(events.compactMap(\.location)).first
        }
        if keeper.url == nil { keeper.url = events.compactMap(\.url).first }
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
