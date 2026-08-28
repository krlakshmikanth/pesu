import AppKit

@MainActor
final class MeetingListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let meetings: [Meeting]
    private let onOpen: ((Meeting) -> Void)?
    private let tableView = NSTableView()
    private let cellIdentifier = NSUserInterfaceItemIdentifier("MeetingRow")

    init(meetings: [Meeting], onOpen: ((Meeting) -> Void)? = nil) {
        self.meetings = meetings
        self.onOpen = onOpen
        super.init(frame: .zero)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Meeting"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 76
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = PesuTheme.muted.withAlphaComponent(0.14)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(openSelectedMeeting)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tableView
        addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func numberOfRows(in tableView: NSTableView) -> Int { meetings.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? MeetingRowCell ?? MeetingRowCell(identifier: cellIdentifier)
        cell.update(with: meetings[row])
        return cell
    }

    @objc private func openSelectedMeeting() {
        guard let onOpen, tableView.clickedRow >= 0, tableView.clickedRow < meetings.count else { return }
        onOpen(meetings[tableView.clickedRow])
    }
}

@MainActor
private final class MeetingRowCell: NSTableCellView {
    private let dateLabel = label("", size: 9, weight: .bold, color: PesuTheme.muted, lines: 2)
    private let titleLabel = label("", size: 14, weight: .bold)
    private let detailLabel = label("", size: 10, color: PesuTheme.muted)
    private let timeLabel = label("", size: 11, weight: .bold)
    private let durationLabel = label("", size: 9, color: PesuTheme.muted)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        let copy = vertical([titleLabel, detailLabel], spacing: 5)
        let timing = vertical([timeLabel, durationLabel], spacing: 4)
        timing.alignment = .trailing
        let row = horizontal([dateLabel, copy, flexibleSpace(), timing], spacing: 22)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            dateLabel.widthAnchor.constraint(equalToConstant: 70),
            timing.widthAnchor.constraint(greaterThanOrEqualToConstant: 82)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(with meeting: Meeting) {
        dateLabel.stringValue = meeting.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
        titleLabel.stringValue = meeting.title
        let people = meeting.participants.joined(separator: ", ")
        detailLabel.stringValue = people.isEmpty ? meeting.summary : people
        timeLabel.stringValue = meeting.isAllDay ? "All day" : meeting.startedAt.formatted(date: .omitted, time: .shortened)
        durationLabel.stringValue = meeting.isAllDay ? (meeting.calendarName ?? "Apple Calendar") : meeting.duration.minuteString
        setAccessibilityLabel("\(meeting.title), \(dateLabel.stringValue), \(timeLabel.stringValue)")
    }
}
