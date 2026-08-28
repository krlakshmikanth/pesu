import AppKit

@MainActor
final class MeetingHeatmapView: NSView {
    private let dailyDurations: [Date: TimeInterval]
    private let rangeEnd: Date
    private let calendar: Calendar

    init(dailyDurations: [Date: TimeInterval], rangeEnd: Date, calendar: Calendar = .current) {
        self.dailyDurations = dailyDurations
        self.rangeEnd = calendar.startOfDay(for: rangeEnd)
        self.calendar = calendar
        super.init(frame: .zero)
        setAccessibilityLabel("Meeting intensity heatmap for the last year")
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 690, height: 116) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let cell: CGFloat = 9
        let gap: CGFloat = 3
        let left: CGFloat = 30
        let top: CGFloat = 23
        let yearStart = calendar.date(byAdding: .day, value: -364, to: rangeEnd) ?? rangeEnd
        let weekday = calendar.component(.weekday, from: yearStart)
        let gridStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: yearStart) ?? yearStart

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: PesuTheme.muted
        ]
        for (row, value) in [(1, "Mon"), (3, "Wed"), (5, "Fri")] {
            let y = bounds.height - top - CGFloat(row) * (cell + gap) - cell
            value.draw(at: NSPoint(x: 0, y: y), withAttributes: textAttributes)
        }

        var lastMonth = -1
        for index in 0..<(53 * 7) {
            guard let date = calendar.date(byAdding: .day, value: index, to: gridStart), date <= rangeEnd else { continue }
            let column = index / 7
            let row = index % 7
            let x = left + CGFloat(column) * (cell + gap)
            let y = bounds.height - top - CGFloat(row) * (cell + gap) - cell
            let day = calendar.startOfDay(for: date)
            let minutes = (dailyDurations[day] ?? 0) / 60
            intensityColor(minutes: minutes).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cell, height: cell), xRadius: 2, yRadius: 2).fill()

            let month = calendar.component(.month, from: date)
            if row == 0, month != lastMonth, column > 0 {
                lastMonth = month
                date.formatted(.dateTime.month(.abbreviated)).draw(
                    at: NSPoint(x: x, y: bounds.height - 11),
                    withAttributes: textAttributes
                )
            }
        }
    }

    private func intensityColor(minutes: Double) -> NSColor {
        switch minutes {
        case 0: PesuTheme.line.withAlphaComponent(0.55)
        case ..<30: PesuTheme.coral.withAlphaComponent(0.22)
        case ..<60: PesuTheme.coral.withAlphaComponent(0.42)
        case ..<120: PesuTheme.coral.withAlphaComponent(0.68)
        default: PesuTheme.coral
        }
    }
}

@MainActor
final class LifeDotsView: NSView {
    private let meetingDays: Set<Date>
    private let rangeEnd: Date
    private let calendar: Calendar

    init(dailyDurations: [Date: TimeInterval], rangeEnd: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        self.rangeEnd = calendar.startOfDay(for: rangeEnd)
        self.meetingDays = Set(dailyDurations.keys.map(calendar.startOfDay(for:)))
        super.init(frame: .zero)
        setAccessibilityLabel("365 day life dots, with meeting days highlighted")
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 330, height: 132) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let columns = 31
        let dot: CGFloat = 5
        let gap: CGFloat = 4
        let start = calendar.date(byAdding: .day, value: -364, to: rangeEnd) ?? rangeEnd

        for index in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else { continue }
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * (dot + gap)
            let y = bounds.height - CGFloat(row + 1) * (dot + gap)
            (meetingDays.contains(calendar.startOfDay(for: date)) ? PesuTheme.coral : PesuTheme.line).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
        }
    }
}
