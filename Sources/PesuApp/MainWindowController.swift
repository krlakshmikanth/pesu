import AppKit
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController {
    private let model: AppModel
    private let splitController = NSSplitViewController()
    private let sidebarController = NSViewController()
    private let contentController = NSViewController()
    private let sidebarHost = NSView()
    private let contentHost = NSView()
    private var sidebarItem: NSSplitViewItem!
    private var renderedScreen: AppScreen?
    private var renderScheduled = false
    private var needsFullPageRender = true
    private var usesCompactLayout = false
    private var recordingBindings: RecordingBindings?
    private var sidebarToolbarItem: NSToolbarItem?
    private var sidebarCollapsedBeforeRecording: Bool?
    private var titleSheet: NSWindow?
    private var workspaceSheetController: DaytonaWorkspaceSheetController?

    private struct RecordingBindings {
        let captureStatus: NSTextField
        let timer: NSTextField
        let transcript: NSTextField
        let speechStatus: NSTextField
        let segmentCount: NSTextField
        let stopButton: NSButton
    }

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pēsu"
        window.minSize = NSSize(width: 720, height: 560)
        window.backgroundColor = PesuTheme.paper
        super.init(window: window)
        configureWindow()
        model.onChange = { [weak self] in self?.scheduleRender() }
        render()
    }

    required init?(coder: NSCoder) { nil }

    func beginNewRecordingFromMenu() {
        guard model.screen != .recording, titleSheet == nil else { return }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        requestMeetingNameAndStart()
    }

    func showSettingsFromMenu() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        model.showSettings()
    }

    private func configureWindow() {
        guard let window else { return }
        window.delegate = self
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .aqua)

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("PesuMainToolbar"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        sidebarHost.setBackground(PesuTheme.sidebar)
        contentHost.setBackground(PesuTheme.paper)
        sidebarController.view = sidebarHost
        contentController.view = contentHost
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 168
        sidebarItem.maximumThickness = 232
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .defaultHigh
        let contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = 520
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(contentItem)
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
    }

    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.renderScheduled = false
            self.render()
        }
    }

    private func render() {
        let screenChanged = renderedScreen != model.screen
        if screenChanged {
            updateRecordingFocusMode(from: renderedScreen, to: model.screen)
        }
        if !screenChanged, !needsFullPageRender, model.screen == .recording, recordingBindings != nil {
            updateRecordingView()
            return
        }

        recordingBindings = nil
        install(makeSidebar(), in: sidebarHost)
        let page: NSView
        switch model.screen {
        case .present: page = makePresent()
        case .past: page = makePast()
        case .future: page = makeFuture()
        case .stats: page = makeStats()
        case .settings: page = makeSettings()
        case .recording: page = makeRecording()
        case .summary: page = makeSummary()
        }
        install(page, in: contentHost)
        renderedScreen = model.screen
        needsFullPageRender = false
    }

    private func updateRecordingFocusMode(from previousScreen: AppScreen?, to nextScreen: AppScreen) {
        if nextScreen == .recording {
            sidebarCollapsedBeforeRecording = sidebarItem.isCollapsed
            sidebarItem.isCollapsed = true
            sidebarToolbarItem?.isEnabled = false
        } else if previousScreen == .recording {
            if let wasCollapsed = sidebarCollapsedBeforeRecording {
                sidebarItem.isCollapsed = wasCollapsed
            }
            sidebarCollapsedBeforeRecording = nil
            sidebarToolbarItem?.isEnabled = true
        }
    }

    private func install(_ view: NSView, in host: NSView) {
        host.subviews.forEach { $0.removeFromSuperview() }
        host.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }

    private func updateRecordingView() {
        guard let bindings = recordingBindings else { return }
        bindings.captureStatus.stringValue = model.captureStatus
        bindings.timer.stringValue = model.recordingDuration.clockString
        bindings.transcript.stringValue = model.liveTranscriptDisplay
        bindings.speechStatus.stringValue = model.speechStatus
        bindings.segmentCount.stringValue = "\(model.liveTranscriptSegments.count) transcript segments"
        bindings.stopButton.isEnabled = model.isRecording
    }

    private func makeSidebar() -> NSView {
        let view = NSView()
        view.setBackground(PesuTheme.sidebar)

        let mark = NSImageView()
        mark.image = Bundle.main.url(forResource: "pesu-logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.setAccessibilityLabel("Pēsu logo")
        let markView = NSView()
        markView.setBackground(.white, cornerRadius: 13)
        markView.addSubview(mark)
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            markView.widthAnchor.constraint(equalToConstant: 56), markView.heightAnchor.constraint(equalToConstant: 56),
            mark.leadingAnchor.constraint(equalTo: markView.leadingAnchor, constant: 1),
            mark.trailingAnchor.constraint(equalTo: markView.trailingAnchor, constant: -1),
            mark.topAnchor.constraint(equalTo: markView.topAnchor, constant: 1),
            mark.bottomAnchor.constraint(equalTo: markView.bottomAnchor, constant: -1)
        ])
        let brand = horizontal([markView, label("Pēsu", size: 22, weight: .bold)], spacing: 11)

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let summaryIsPast = model.screen == .summary && model.selectedMeeting.startedAt < today
        let summaryIsPresent = model.screen == .summary && model.selectedMeeting.startedAt >= today && model.selectedMeeting.startedAt < tomorrow
        let summaryIsFuture = model.screen == .summary && model.selectedMeeting.startedAt >= tomorrow
        let presentActive = model.screen == .present || model.screen == .recording || summaryIsPresent
        let pastActive = model.screen == .past || summaryIsPast
        let futureActive = model.screen == .future || summaryIsFuture
        let statsActive = model.screen == .stats
        let settingsActive = model.screen == .settings
        let present = sidebarButton("Present", active: presentActive) { self.model.showPresent() }
        let past = sidebarButton("Past", active: pastActive) { self.model.showPast() }
        let future = sidebarButton("Future", active: futureActive) { self.model.showFuture() }
        let stats = model.isStatsTabEnabled ? sidebarButton("Stats", active: statsActive) { self.model.showStats() } : nil

        let settings = sidebarButton("Settings", active: settingsActive) { self.model.showSettings() }
        let statusDot = NSView()
        statusDot.setBackground(PesuTheme.green, cornerRadius: 4)
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([statusDot.widthAnchor.constraint(equalToConstant: 8), statusDot.heightAnchor.constraint(equalToConstant: 8)])
        let status = horizontal([statusDot, label("Local on this Mac", size: 10, color: PesuTheme.muted)], spacing: 7)
        let store = label(model.storeStatus, size: 8, color: PesuTheme.muted.withAlphaComponent(0.75), lines: 2)

        var sidebarViews: [NSView] = [brand, present, past, future]
        if let stats { sidebarViews.append(stats) }
        sidebarViews.append(contentsOf: [settings, status, store])
        sidebarViews.forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        var constraints = [
            brand.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18), brand.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            present.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), present.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), present.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 38), present.heightAnchor.constraint(equalToConstant: 42),
            past.leadingAnchor.constraint(equalTo: present.leadingAnchor), past.trailingAnchor.constraint(equalTo: present.trailingAnchor), past.topAnchor.constraint(equalTo: present.bottomAnchor, constant: 3), past.heightAnchor.constraint(equalToConstant: 41),
            future.leadingAnchor.constraint(equalTo: present.leadingAnchor), future.trailingAnchor.constraint(equalTo: present.trailingAnchor), future.topAnchor.constraint(equalTo: past.bottomAnchor, constant: 3), future.heightAnchor.constraint(equalToConstant: 41),
            settings.leadingAnchor.constraint(equalTo: present.leadingAnchor), settings.trailingAnchor.constraint(equalTo: present.trailingAnchor), settings.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -22), settings.heightAnchor.constraint(equalToConstant: 41),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 31), status.bottomAnchor.constraint(equalTo: store.topAnchor, constant: -5),
            store.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 31), store.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), store.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -22)
        ]
        if let stats {
            constraints.append(contentsOf: [
                stats.leadingAnchor.constraint(equalTo: present.leadingAnchor),
                stats.trailingAnchor.constraint(equalTo: present.trailingAnchor),
                stats.topAnchor.constraint(equalTo: future.bottomAnchor, constant: 3),
                stats.heightAnchor.constraint(equalToConstant: 41)
            ])
        }
        NSLayoutConstraint.activate(constraints)
        return view
    }

    private func sidebarButton(_ title: String, active: Bool, action: @escaping () -> Void) -> NSButton {
        let button = ActionButton(title: title, handler: action)
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: active ? .bold : .regular)
        button.contentTintColor = active ? PesuTheme.ink : PesuTheme.muted
        button.setBackground(active ? .white : .clear, cornerRadius: 9)
        return button
    }

    private func makePresent() -> NSView {
        let page = NSView(); page.setBackground(PesuTheme.paper)
        let todayLabel = Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning." : (hour < 18 ? "Good afternoon." : "Good evening.")
        let titleBlock = vertical([kicker(todayLabel), label(greeting, size: usesCompactLayout ? 46 : 58, weight: .semibold, serif: true, lines: 2)], spacing: 8)
        let header = horizontal([titleBlock, flexibleSpace(), newRecordingButton()], spacing: 20)
        let meetingsHeader = horizontal([label("Today", size: 13, weight: .bold), flexibleSpace(), label("\(model.presentMeetings.count) meetings", size: 10, color: PesuTheme.muted)])

        let stack = vertical([header, meetingsHeader], spacing: 0)
        stack.setCustomSpacing(44, after: header)
        if !model.presentDuplicateGroups.isEmpty {
            let duplicates = makeDuplicateCard(groups: model.presentDuplicateGroups, scope: .present)
            stack.addArrangedSubview(duplicates)
            stack.setCustomSpacing(14, after: meetingsHeader)
            stack.setCustomSpacing(18, after: duplicates)
        }
        if !model.duplicateNotice.isEmpty {
            let notice = label(model.duplicateNotice, size: 10, weight: .medium, color: PesuTheme.muted)
            stack.addArrangedSubview(notice)
            stack.setCustomSpacing(14, after: notice)
        }
        if model.presentMeetings.isEmpty {
            let message = model.isCalendarConnected ? "No meetings are scheduled today." : "Connect Apple Calendar in Settings to see today’s meetings."
            stack.addArrangedSubview(label(message, size: 13, color: PesuTheme.muted))
            stack.setCustomSpacing(28, after: meetingsHeader)
        }
        page.addSubview(stack)
        let pageInset: CGFloat = usesCompactLayout ? 36 : 74
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: pageInset),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -pageInset),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: usesCompactLayout ? 42 : 70)
        ])
        if !model.presentMeetings.isEmpty {
            let list = MeetingListView(meetings: model.presentMeetings) { self.model.open($0) }
            page.addSubview(list)
            list.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                list.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
                list.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 14),
                list.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -24)
            ])
        }
        return page
    }

    private func makePast() -> NSView {
        let page = NSView(); page.setBackground(PesuTheme.paper)
        let titleBlock = vertical([kicker("HISTORY"), label("Past meetings", size: usesCompactLayout ? 44 : 54, weight: .semibold, serif: true, lines: 2)], spacing: 8)
        let header = horizontal([titleBlock, flexibleSpace(), newRecordingButton()])
        let listHeader = horizontal([label("Before today", size: 12, weight: .bold), flexibleSpace(), label("\(model.pastMeetings.count) meetings", size: 10, weight: .bold, color: PesuTheme.muted)])
        let top = vertical([header, listHeader], spacing: 0)
        top.setCustomSpacing(42, after: header)
        if !model.futureDuplicateGroups.isEmpty {
            let duplicates = makeDuplicateCard(groups: model.futureDuplicateGroups, scope: .future)
            top.addArrangedSubview(duplicates)
            top.setCustomSpacing(14, after: listHeader)
            top.setCustomSpacing(16, after: duplicates)
        }
        if !model.duplicateNotice.isEmpty {
            let notice = label(model.duplicateNotice, size: 10, weight: .medium, color: PesuTheme.muted)
            top.addArrangedSubview(notice)
            top.setCustomSpacing(12, after: notice)
        }
        page.addSubview(top)
        let pageInset: CGFloat = usesCompactLayout ? 36 : 74
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: pageInset),
            top.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -pageInset),
            top.topAnchor.constraint(equalTo: page.topAnchor, constant: usesCompactLayout ? 48 : 82)
        ])
        if model.pastMeetings.isEmpty {
            let message = model.isCalendarConnected ? "No past meetings were found." : "Connect Apple Calendar in Settings to see past meetings."
            let empty = label(message, size: 13, color: PesuTheme.muted)
            page.addSubview(empty)
            NSLayoutConstraint.activate([empty.leadingAnchor.constraint(equalTo: top.leadingAnchor), empty.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 28)])
        } else {
            let list = MeetingListView(meetings: model.pastMeetings) { self.model.open($0) }
            page.addSubview(list)
            list.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                list.leadingAnchor.constraint(equalTo: top.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: top.trailingAnchor),
                list.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14),
                list.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -28)
            ])
        }
        return page
    }

    private func makeFuture() -> NSView {
        let page = NSView(); page.setBackground(PesuTheme.paper)
        let titleBlock = vertical([kicker("UPCOMING"), label("Future meetings", size: usesCompactLayout ? 44 : 54, weight: .semibold, serif: true, lines: 2)], spacing: 8)
        let header = horizontal([titleBlock, flexibleSpace(), newRecordingButton()], spacing: 20)
        let listHeader = horizontal([
            label("From tomorrow", size: 12, weight: .bold),
            flexibleSpace(),
            label("\(model.futureMeetings.count) meetings · \(model.futureRangeDescription)", size: 10, weight: .bold, color: PesuTheme.muted)
        ], spacing: 10)
        let loadLater = ActionButton(title: model.isCalendarSyncing ? "Loading…" : "Load later events") { self.model.loadLaterCalendarEvents() }
        loadLater.bezelStyle = .rounded
        loadLater.font = .systemFont(ofSize: 10, weight: .bold)
        loadLater.isEnabled = model.isCalendarConnected && !model.isCalendarSyncing
        let top = vertical([header, listHeader], spacing: 0)
        top.setCustomSpacing(42, after: header)
        page.addSubview(top)
        let pageInset: CGFloat = usesCompactLayout ? 36 : 74
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: pageInset),
            top.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -pageInset),
            top.topAnchor.constraint(equalTo: page.topAnchor, constant: usesCompactLayout ? 48 : 82)
        ])

        if model.futureMeetings.isEmpty {
            let message = model.isCalendarConnected ? "No meetings are scheduled from tomorrow onward." : "Connect Apple Calendar in Settings to see future meetings."
            let empty = label(message, size: 13, color: PesuTheme.muted)
            page.addSubview(empty)
            NSLayoutConstraint.activate([empty.leadingAnchor.constraint(equalTo: top.leadingAnchor), empty.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 28)])
        } else {
            let list = MeetingListView(meetings: model.futureMeetings) { self.model.open($0) }
            page.addSubview(list)
            page.addSubview(loadLater)
            list.translatesAutoresizingMaskIntoConstraints = false
            loadLater.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                list.leadingAnchor.constraint(equalTo: top.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: top.trailingAnchor),
                list.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 14),
                list.bottomAnchor.constraint(equalTo: loadLater.topAnchor, constant: -12),
                loadLater.leadingAnchor.constraint(equalTo: top.leadingAnchor),
                loadLater.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -20),
                loadLater.widthAnchor.constraint(equalToConstant: 150),
                loadLater.heightAnchor.constraint(equalToConstant: 32)
            ])
        }
        return page
    }

    private func makeDuplicateCard(groups: [DuplicateMeetingGroup], scope: DuplicateMeetingScope) -> NSView {
        let copies = groups.reduce(0) { $0 + $1.copiesCount }
        let title = label(
            "\(groups.count) duplicate \(groups.count == 1 ? "meeting" : "meetings") found",
            size: 13,
            weight: .bold
        )
        let detail = label(
            "Pēsu matched the same title, start time and duration. Merge their details, or delete the extra copies while keeping one event.",
            size: 10,
            color: PesuTheme.muted,
            lines: 2
        )
        let count = label("\(copies) extra \(copies == 1 ? "copy" : "copies")", size: 9, weight: .bold, color: PesuTheme.coral)
        let merge = ActionButton(title: "Merge into one") {
            self.confirmDuplicateResolution(scope: scope, strategy: .merge, groupCount: groups.count, copies: copies)
        }
        merge.bezelStyle = .rounded
        merge.font = .systemFont(ofSize: 10, weight: .bold)
        let delete = ActionButton(title: "Delete copies") {
            self.confirmDuplicateResolution(scope: scope, strategy: .keepOne, groupCount: groups.count, copies: copies)
        }
        delete.bezelStyle = .rounded
        delete.font = .systemFont(ofSize: 10, weight: .medium)
        let actions = horizontal([merge, delete], spacing: 8)
        let copy = vertical([horizontal([title, flexibleSpace(), count]), detail, actions], spacing: 9)
        let card = NSView()
        card.setBackground(.white, cornerRadius: 10)
        card.addSubview(copy)
        NSLayoutConstraint.activate([
            copy.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            copy.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            copy.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            copy.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15),
            merge.widthAnchor.constraint(equalToConstant: 118),
            delete.widthAnchor.constraint(equalToConstant: 106)
        ])
        return card
    }

    private func confirmDuplicateResolution(
        scope: DuplicateMeetingScope,
        strategy: DuplicateResolutionStrategy,
        groupCount: Int,
        copies: Int
    ) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strategy == .merge ? "Merge duplicate calendar events?" : "Delete duplicate calendar copies?"
        alert.informativeText = strategy == .merge
            ? "Pēsu will keep the richest event in each of \(groupCount) duplicate sets, combine notes, location and timing, then remove \(copies) extra copies from Apple Calendar."
            : "Pēsu will keep one event in each of \(groupCount) duplicate sets and remove \(copies) extra copies from Apple Calendar."
        alert.addButton(withTitle: strategy == .merge ? "Merge events" : "Delete copies")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.model.resolveDuplicates(in: scope, strategy: strategy)
        }
    }

    private func makeStats() -> NSView {
        let page = NSView()
        page.setBackground(PesuTheme.paper)
        let stats = model.meetingStats
        let range = "\(stats.rangeStart.formatted(.dateTime.day().month(.abbreviated).year()))–\(stats.rangeEnd.formatted(.dateTime.day().month(.abbreviated).year()))"
        let titleBlock = vertical([
            kicker("YOUR MEETING YEAR"),
            label("Time, in perspective", size: usesCompactLayout ? 42 : 52, weight: .semibold, serif: true, lines: 2),
            label("Completed meetings from the last 12 months · \(range)", size: 11, color: PesuTheme.muted)
        ], spacing: 8)

        let metricTop = horizontal([
            statMetricCard(value: "\(stats.completedMeetings)", title: "Meetings completed"),
            statMetricCard(value: durationSummary(stats.totalDuration), title: "Time in meetings")
        ], spacing: 12)
        metricTop.distribution = .fillEqually
        let metricBottom = horizontal([
            statMetricCard(value: durationSummary(stats.averageDuration), title: "Average meeting"),
            statMetricCard(value: "\(stats.meetingDays)", title: "Days with meetings")
        ], spacing: 12)
        metricBottom.distribution = .fillEqually
        let metricGrid = vertical([metricTop, metricBottom], spacing: 12)
        metricGrid.alignment = .width

        let heatmap = MeetingHeatmapView(dailyDurations: stats.dailyDurations, rangeEnd: stats.rangeEnd)
        let heatLegend = horizontal([
            label("Less", size: 8, color: PesuTheme.muted),
            intensityDot(PesuTheme.line),
            intensityDot(PesuTheme.coral.withAlphaComponent(0.22)),
            intensityDot(PesuTheme.coral.withAlphaComponent(0.48)),
            intensityDot(PesuTheme.coral),
            label("More", size: 8, color: PesuTheme.muted)
        ], spacing: 5)
        let heatTitle = horizontal([
            vertical([
                label("Meeting intensity", size: 17, weight: .bold),
                label("Daily meeting time across the last year", size: 10, color: PesuTheme.muted)
            ], spacing: 4),
            flexibleSpace(),
            heatLegend
        ])
        let heatStack = vertical([heatTitle, heatmap], spacing: 18)
        let heatCard = statsCard(containing: heatStack)
        NSLayoutConstraint.activate([heatmap.heightAnchor.constraint(equalToConstant: 116)])

        let patternRow = horizontal([
            patternCard(title: "Busiest day", highlight: stats.busiestDay),
            patternCard(title: "Busiest week", highlight: stats.busiestWeek),
            patternCard(title: "Busiest month", highlight: stats.busiestMonth)
        ], spacing: 12)
        patternRow.distribution = .fillEqually

        let lifetimePercent = stats.globalAverageLifetimeDays == 0
            ? 0
            : (Double(stats.meetingDays) / Double(stats.globalAverageLifetimeDays)) * 100
        let lifeCopy = vertical([
            label("Dots in our life", size: 17, weight: .bold),
            label("Each dot is one day in the last year. Coral marks a day that included at least one completed meeting.", size: 10, color: PesuTheme.muted, lines: 3),
            label("\(stats.meetingDays) meeting days", size: 27, weight: .semibold, serif: true),
            label("\(String(format: "%.3f", lifetimePercent))% of the \(stats.globalAverageLifetimeDays) days in a 73.3-year average global lifespan.", size: 10, color: PesuTheme.muted, lines: 2),
            label("Reference: UN World Population Prospects 2024", size: 8, weight: .medium, color: PesuTheme.muted.withAlphaComponent(0.8))
        ], spacing: 7)
        let lifeDots = LifeDotsView(dailyDurations: stats.dailyDurations, rangeEnd: stats.rangeEnd)
        let lifeStack = vertical([lifeCopy, lifeDots], spacing: 18)
        lifeStack.alignment = .width
        let lifeCard = statsCard(containing: lifeStack)
        NSLayoutConstraint.activate([
            lifeDots.heightAnchor.constraint(equalToConstant: 132)
        ])

        var sections: [NSView] = [titleBlock, metricGrid, heatCard, patternRow, lifeCard]
        if !model.isCalendarConnected {
            sections.insert(label("Connect Apple Calendar in Settings to fill these statistics with your meeting history.", size: 11, color: PesuTheme.muted), at: 1)
        }
        let content = vertical(sections, spacing: 18)
        content.setCustomSpacing(30, after: titleBlock)

        let document = FlippedView()
        document.addSubview(content)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        page.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        let pageInset: CGFloat = usesCompactLayout ? 32 : 64
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: page.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: pageInset),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -pageInset),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 56),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -54)
        ])
        return page
    }

    private func statMetricCard(value: String, title: String) -> NSView {
        let stack = vertical([
            label(value, size: 28, weight: .semibold, serif: true),
            label(title, size: 9, weight: .bold, color: PesuTheme.muted)
        ], spacing: 7)
        return statsCard(containing: stack, inset: 18)
    }

    private func patternCard(title: String, highlight: MeetingPeriodHighlight) -> NSView {
        let stack = vertical([
            label(title.uppercased(), size: 8, weight: .bold, color: PesuTheme.coral),
            label(highlight.label, size: 15, weight: .bold, lines: 2),
            label(durationSummary(highlight.duration), size: 10, color: PesuTheme.muted)
        ], spacing: 7)
        return statsCard(containing: stack, inset: 18)
    }

    private func statsCard(containing content: NSView, inset: CGFloat = 22) -> NSView {
        let card = NSView()
        card.setBackground(.white, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset)
        ])
        return card
    }

    private func intensityDot(_ color: NSColor) -> NSView {
        let dot = NSView()
        dot.setBackground(color, cornerRadius: 2)
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9)
        ])
        return dot
    }

    private func durationSummary(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        if minutes == 0 { return "0 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) m"
    }

    private func makeSettings() -> NSView {
        let page = NSView(); page.setBackground(PesuTheme.paper)
        let titleBlock = vertical([kicker("PREFERENCES"), label("Settings", size: usesCompactLayout ? 44 : 54, weight: .semibold, serif: true)], spacing: 8)

        let calendarTitle = label("Apple Calendar", size: 20, weight: .bold)
        let statusDot = NSView()
        statusDot.setBackground(model.isCalendarConnected ? PesuTheme.green : PesuTheme.muted.withAlphaComponent(0.5), cornerRadius: 5)
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([statusDot.widthAnchor.constraint(equalToConstant: 10), statusDot.heightAnchor.constraint(equalToConstant: 10)])
        let status = horizontal([statusDot, label(model.calendarStatus, size: 11, weight: .bold)], spacing: 8)
        let detail = label(model.calendarDetail, size: 12, color: PesuTheme.muted, lines: 3)
        let privacy = label("Pēsu reads events directly from Apple Calendar on this Mac. Calendar data is not uploaded.", size: 10, color: PesuTheme.muted, lines: 3)
        let range = label("Calendar history: one year. Future: no fixed limit; later years load from the Future tab.", size: 10, color: PesuTheme.muted, lines: 2)
        let connect = ActionButton(title: model.calendarButtonTitle) { self.model.connectOrRefreshCalendar() }
        connect.bezelStyle = .rounded
        connect.font = .systemFont(ofSize: 11, weight: .bold)
        connect.isEnabled = model.canRequestCalendarAccess && !model.isCalendarSyncing

        let cardStack = vertical([calendarTitle, status, detail, privacy, range, connect], spacing: 12)
        cardStack.setCustomSpacing(20, after: calendarTitle)
        cardStack.setCustomSpacing(22, after: range)
        let card = NSView(); card.setBackground(.white, cornerRadius: 12); card.addSubview(cardStack)
        let pageInset: CGFloat = usesCompactLayout ? 36 : 74
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -26),
            connect.widthAnchor.constraint(equalToConstant: 190),
            connect.heightAnchor.constraint(equalToConstant: 36)
        ])

        let recordingCard = makeRecordingSettingsCard()
        let daytonaCard = makeDaytonaSettingsCard()
        let openAICard = makeOpenAISettingsCard()
        let sidebarCard = makeSidebarSettingsCard()
        let sourcesCard = makeCalendarSourcesCard()
        let stack = vertical([titleBlock, card, recordingCard, daytonaCard, openAICard, sidebarCard, sourcesCard], spacing: 22)
        stack.setCustomSpacing(38, after: titleBlock)

        let document = FlippedView()
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        page.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: page.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: pageInset),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -pageInset),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 64),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -54)
        ])
        return page
    }

    private func makeRecordingSettingsCard() -> NSView {
        let title = label("Recording", size: 17, weight: .bold)
        let explanation = label(
            "Choose the microphone used for both the local audio file and live on-device transcription. System Default follows macOS automatically.",
            size: 10,
            color: PesuTheme.muted,
            lines: 3
        )
        let microphoneLabel = label("Microphone", size: 10, weight: .bold)
        let picker = ActionPopUpButton(
            options: model.microphones,
            selectedID: model.selectedMicrophoneID
        ) { id in
            self.model.selectMicrophone(id)
        }
        picker.font = .systemFont(ofSize: 11, weight: .medium)
        picker.setAccessibilityLabel("Recording microphone")
        picker.isEnabled = !model.isRecording
        let refresh = ActionButton(title: "Refresh devices") { self.model.refreshAudioDevices() }
        refresh.font = .systemFont(ofSize: 10, weight: .medium)
        refresh.isEnabled = !model.isRecording
        let selection = horizontal([microphoneLabel, flexibleSpace(), picker, refresh], spacing: 10)
        let detail = label(model.selectedMicrophone.detail, size: 9, color: PesuTheme.muted)
        let speechModel = horizontal([
            vertical([
                label("Live transcription", size: 10, weight: .bold),
                label("Apple Speech", size: 9, color: PesuTheme.muted)
            ], spacing: 3),
            flexibleSpace(),
            label(model.speechModelStatus, size: 9, weight: .medium, color: PesuTheme.muted)
        ])
        let summaryModel = horizontal([
            vertical([
                label("Meeting summaries", size: 10, weight: .bold),
                label("Apple Intelligence", size: 9, color: PesuTheme.muted)
            ], spacing: 3),
            flexibleSpace(),
            label(model.summaryModelStatus, size: 9, weight: .medium, color: PesuTheme.muted)
        ])
        let privacy = horizontal([
            intensityDot(PesuTheme.green),
            label("Both models run on device; audio, transcript and summary stay on this Mac.", size: 9, weight: .medium, color: PesuTheme.muted)
        ], spacing: 7)
        let content = vertical([title, explanation, selection, detail, separator(), speechModel, summaryModel, privacy], spacing: 10)
        content.setCustomSpacing(18, after: explanation)
        content.setCustomSpacing(14, after: detail)
        content.setCustomSpacing(14, after: summaryModel)

        let card = NSView()
        card.setBackground(.white, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            picker.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            refresh.widthAnchor.constraint(equalToConstant: 110)
        ])
        return card
    }

    private func makeDaytonaSettingsCard() -> NSView {
        let title = label("Daytona", size: 17, weight: .bold)
        let explanation = label(
            "Add your Daytona API key to enable Build from this meeting. Pēsu stores it in macOS Keychain; it is never included in meeting context or written to the local database.",
            size: 10,
            color: PesuTheme.muted,
            lines: 3
        )
        let status = horizontal([
            intensityDot(model.hasDaytonaAPIKey ? PesuTheme.green : PesuTheme.muted.withAlphaComponent(0.5)),
            label(model.daytonaCredentialStatus, size: 10, weight: .medium, color: PesuTheme.muted)
        ], spacing: 7)

        let field = NSSecureTextField(string: "")
        field.placeholderString = model.hasDaytonaAPIKey
            ? "Enter a new key to replace the saved key"
            : "Daytona API key"
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel("Daytona API key")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let save = ActionButton(title: model.hasDaytonaAPIKey ? "Update key" : "Save key") { [weak self, weak field] in
            guard let self, let field else { return }
            do {
                try self.model.saveDaytonaAPIKey(field.stringValue)
                field.stringValue = ""
            } catch {
                self.showAlert(message: "Could not save the Daytona key", detail: error.localizedDescription)
            }
        }
        save.font = .systemFont(ofSize: 10, weight: .bold)
        save.bezelStyle = .rounded
        save.setAccessibilityLabel(model.hasDaytonaAPIKey ? "Update Daytona API key" : "Save Daytona API key")

        let remove = ActionButton(title: "Remove key") { [weak self] in
            guard let self else { return }
            do {
                try self.model.removeDaytonaAPIKey()
            } catch {
                self.showAlert(message: "Could not remove the Daytona key", detail: error.localizedDescription)
            }
        }
        remove.isBordered = false
        remove.font = .systemFont(ofSize: 10, weight: .medium)
        remove.contentTintColor = PesuTheme.coral
        remove.isHidden = !model.hasDaytonaAPIKey
        remove.setAccessibilityLabel("Remove Daytona API key")

        let entry = horizontal([field, save, remove], spacing: 10)
        let bridgeCopy = label(
            "Pēsu reads the key only when you create a workspace and sends it solely to the localhost bridge as an authorization credential.",
            size: 9,
            color: PesuTheme.muted,
            lines: 2
        )
        let content = vertical([title, explanation, status, entry, bridgeCopy], spacing: 10)
        content.setCustomSpacing(18, after: explanation)
        content.setCustomSpacing(14, after: status)

        let card = NSView()
        card.setBackground(.white, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),
            save.widthAnchor.constraint(equalToConstant: 96)
        ])
        return card
    }

    private func makeOpenAISettingsCard() -> NSView {
        let title = label("OpenAI", size: 17, weight: .bold)
        let explanation = label(
            "Add an OpenAI API key for the Codex agent used by Build from this meeting. Pēsu stores it in macOS Keychain and retrieves it automatically for future builds.",
            size: 10,
            color: PesuTheme.muted,
            lines: 3
        )
        let status = horizontal([
            intensityDot(model.hasOpenAIAPIKey ? PesuTheme.green : PesuTheme.muted.withAlphaComponent(0.5)),
            label(model.openAICredentialStatus, size: 10, weight: .medium, color: PesuTheme.muted)
        ], spacing: 7)

        let field = NSSecureTextField(string: "")
        field.placeholderString = model.hasOpenAIAPIKey
            ? "Enter a new key to replace the saved key"
            : "OpenAI API key"
        field.font = .systemFont(ofSize: 12, weight: .medium)
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel("OpenAI API key")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let save = ActionButton(title: model.hasOpenAIAPIKey ? "Update key" : "Save key") { [weak self, weak field] in
            guard let self, let field else { return }
            do {
                try self.model.saveOpenAIAPIKey(field.stringValue)
                field.stringValue = ""
            } catch {
                self.showAlert(message: "Could not save the OpenAI key", detail: error.localizedDescription)
            }
        }
        save.font = .systemFont(ofSize: 10, weight: .bold)
        save.bezelStyle = .rounded
        save.setAccessibilityLabel(model.hasOpenAIAPIKey ? "Update OpenAI API key" : "Save OpenAI API key")

        let remove = ActionButton(title: "Remove key") { [weak self] in
            guard let self else { return }
            do {
                try self.model.removeOpenAIAPIKey()
            } catch {
                self.showAlert(message: "Could not remove the OpenAI key", detail: error.localizedDescription)
            }
        }
        remove.isBordered = false
        remove.font = .systemFont(ofSize: 10, weight: .medium)
        remove.contentTintColor = PesuTheme.coral
        remove.isHidden = !model.hasOpenAIAPIKey
        remove.setAccessibilityLabel("Remove OpenAI API key")

        let entry = horizontal([field, save, remove], spacing: 10)
        let privacy = label(
            "Only after you approve a build, Pēsu sends the key through its authenticated localhost bridge to that one Daytona agent session. It is never added to meeting context, generated files, or Pēsu's database.",
            size: 9,
            color: PesuTheme.muted,
            lines: 3
        )
        let content = vertical([title, explanation, status, entry, privacy], spacing: 10)
        content.setCustomSpacing(18, after: explanation)
        content.setCustomSpacing(14, after: status)

        let card = NSView()
        card.setBackground(.white, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),
            save.widthAnchor.constraint(equalToConstant: 96)
        ])
        return card
    }

    private func makeSidebarSettingsCard() -> NSView {
        let title = label("Sidebar", size: 17, weight: .bold)
        let statsCopy = vertical([
            label("Show Stats tab", size: 11, weight: .bold),
            label("Keep meeting statistics available in the main sidebar.", size: 9, color: PesuTheme.muted)
        ], spacing: 4)
        let statsToggle = ActionSwitch(isOn: model.isStatsTabEnabled) { enabled in
            self.model.setStatsTabEnabled(enabled)
        }
        statsToggle.setAccessibilityLabel("Show Stats tab")
        let statsRow = horizontal([statsCopy, flexibleSpace(), statsToggle], spacing: 14)

        let decisionsCopy = vertical([
            label("Show Decisions", size: 11, weight: .bold),
            label("Include the Decisions section on meeting notes.", size: 9, color: PesuTheme.muted)
        ], spacing: 4)
        let decisionsToggle = ActionSwitch(isOn: model.isDecisionsEnabled) { enabled in
            self.model.setDecisionsEnabled(enabled)
        }
        decisionsToggle.setAccessibilityLabel("Show Decisions")
        let decisionsRow = horizontal([decisionsCopy, flexibleSpace(), decisionsToggle], spacing: 14)
        let content = vertical([title, statsRow, separator(), decisionsRow], spacing: 18)

        let card = NSView()
        card.setBackground(.white, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
        return card
    }

    private func makeCalendarSourcesCard() -> NSView {
        let title = horizontal([
            label("Included calendars", size: 17, weight: .bold),
            flexibleSpace(),
            label("\(model.enabledCalendarCount) of \(model.calendarSources.count) enabled", size: 9, weight: .bold, color: PesuTheme.muted)
        ])
        let explanation = label(
            "Only enabled calendars appear in Past, Present, Future, duplicate checks and Stats. Birthdays, holidays and daylight-saving calendars start disabled.",
            size: 10,
            color: PesuTheme.muted,
            lines: 3
        )
        let content = vertical([title, explanation], spacing: 8)
        content.setCustomSpacing(18, after: explanation)

        if !model.isCalendarConnected {
            content.addArrangedSubview(label("Connect Apple Calendar above to choose which calendars Pēsu includes.", size: 11, color: PesuTheme.muted))
        } else if model.calendarSources.isEmpty {
            content.addArrangedSubview(label("No Apple Calendar sources are available.", size: 11, color: PesuTheme.muted))
        } else {
            for (index, source) in model.calendarSources.enumerated() {
                if index > 0 { content.addArrangedSubview(separator()) }
                content.addArrangedSubview(makeCalendarSourceRow(source))
            }
        }

        let card = NSView()
        card.setBackground(.white, cornerRadius: 12)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
        return card
    }

    private func makeCalendarSourceRow(_ source: CalendarSourceOption) -> NSView {
        var titleViews: [NSView] = [label(source.title, size: 12, weight: .bold)]
        if source.isSuggestedDefaultOff {
            titleViews.append(label("Recommended off", size: 8, weight: .bold, color: PesuTheme.coral))
        }
        let sourceTitle = horizontal(titleViews, spacing: 8)
        let copy = vertical([
            sourceTitle,
            label(source.accountTitle, size: 9, color: PesuTheme.muted)
        ], spacing: 4)
        let toggle = ActionSwitch(isOn: source.isEnabled) { enabled in
            self.model.setCalendarSource(source.id, enabled: enabled)
        }
        toggle.isEnabled = !model.isCalendarSyncing
        toggle.setAccessibilityLabel("Include \(source.title) calendar")
        let row = horizontal([copy, flexibleSpace(), toggle], spacing: 14)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return row
    }

    private func makeRecording() -> NSView {
        let page = NSView()
        page.setBackground(NSColor(red: 0.055, green: 0.063, blue: 0.058, alpha: 1))
        let cancel = ActionButton(title: "Cancel") { self.model.cancelRecording() }
        cancel.isBordered = false
        cancel.font = .systemFont(ofSize: 12, weight: .medium)
        cancel.contentTintColor = .white.withAlphaComponent(0.72)
        let status = label(model.captureStatus, size: 10, weight: .medium, color: .white.withAlphaComponent(0.58))
        status.alignment = .right
        let header = horizontal([cancel, flexibleSpace(), status], spacing: 12)

        let liveDot = intensityDot(PesuTheme.coral)
        let liveLabel = label("RECORDING", size: 9, weight: .bold, color: PesuTheme.coral)
        let livePill = horizontal([liveDot, liveLabel], spacing: 7)
        livePill.edgeInsets = NSEdgeInsets(top: 7, left: 11, bottom: 7, right: 11)
        livePill.setBackground(PesuTheme.coral.withAlphaComponent(0.12), cornerRadius: 14)

        let meetingTitle = label(model.recordingTitle, size: usesCompactLayout ? 25 : 30, weight: .semibold, color: .white, lines: 2)
        meetingTitle.alignment = .center
        let timer = label(model.recordingDuration.clockString, size: usesCompactLayout ? 68 : 84, weight: .medium, color: .white)
        timer.font = .monospacedDigitSystemFont(ofSize: usesCompactLayout ? 68 : 84, weight: .medium)
        timer.alignment = .center
        let transcript = label(model.liveTranscriptDisplay, size: 15, weight: .regular, color: .white.withAlphaComponent(0.82), lines: 5)
        transcript.alignment = .left
        transcript.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let speechStatus = label(model.speechStatus, size: 10, weight: .medium, color: .white.withAlphaComponent(0.60))
        let speech = horizontal([
            intensityDot(model.isRecording ? PesuTheme.green : PesuTheme.coral),
            speechStatus
        ], spacing: 7)
        let stop = ActionButton(title: "Stop recording") { self.model.stopRecording() }
        stop.isBordered = false
        stop.font = .systemFont(ofSize: 13, weight: .bold)
        stop.contentTintColor = .white
        stop.setBackground(PesuTheme.coral, cornerRadius: 24)
        stop.setAccessibilityLabel("Stop recording")
        stop.isEnabled = model.isRecording
        NSLayoutConstraint.activate([
            stop.widthAnchor.constraint(equalToConstant: 190),
            stop.heightAnchor.constraint(equalToConstant: 48)
        ])

        let segmentCount = label("\(model.liveTranscriptSegments.count) transcript segments", size: 9, color: .white.withAlphaComponent(0.42))
        let transcriptHeader = horizontal([label("Live transcript", size: 11, weight: .bold, color: .white), flexibleSpace(), segmentCount])
        let transcriptContent = vertical([transcriptHeader, transcript, speech], spacing: 13)
        let transcriptCard = NSView()
        transcriptCard.setBackground(.white.withAlphaComponent(0.065), cornerRadius: 18)
        transcriptCard.addSubview(transcriptContent)
        NSLayoutConstraint.activate([
            transcriptContent.leadingAnchor.constraint(equalTo: transcriptCard.leadingAnchor, constant: 22),
            transcriptContent.trailingAnchor.constraint(equalTo: transcriptCard.trailingAnchor, constant: -22),
            transcriptContent.topAnchor.constraint(equalTo: transcriptCard.topAnchor, constant: 18),
            transcriptContent.bottomAnchor.constraint(equalTo: transcriptCard.bottomAnchor, constant: -18),
            transcriptCard.widthAnchor.constraint(lessThanOrEqualToConstant: 650),
            transcriptCard.widthAnchor.constraint(greaterThanOrEqualToConstant: 430)
        ])

        let audioSource = label("System audio and \(model.selectedMicrophone.name)", size: 10, color: .white.withAlphaComponent(0.42))
        let center = vertical([livePill, meetingTitle, timer, stop, audioSource, transcriptCard], spacing: 18)
        center.alignment = .centerX
        center.setCustomSpacing(22, after: livePill)
        center.setCustomSpacing(8, after: meetingTitle)
        center.setCustomSpacing(14, after: timer)
        center.setCustomSpacing(10, after: stop)
        center.setCustomSpacing(26, after: audioSource)

        [header, center].forEach { page.addSubview($0) }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 30),
            header.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -30),
            header.topAnchor.constraint(equalTo: page.topAnchor, constant: 24),
            center.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            center.centerYAnchor.constraint(equalTo: page.centerYAnchor, constant: -10),
            center.leadingAnchor.constraint(greaterThanOrEqualTo: page.leadingAnchor, constant: 36),
            center.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -36),
            transcriptCard.widthAnchor.constraint(lessThanOrEqualTo: page.widthAnchor, constant: -72)
        ])
        recordingBindings = RecordingBindings(
            captureStatus: status,
            timer: timer,
            transcript: transcript,
            speechStatus: speechStatus,
            segmentCount: segmentCount,
            stopButton: stop
        )
        return page
    }

    private func makeSummary() -> NSView {
        let page = NSView(); page.setBackground(PesuTheme.paper)
        let back = ActionButton(title: "All conversations") { self.model.showPresent() }
        back.isBordered = false
        let export = makeExportButton()
        var headerItems: [NSView] = [back, flexibleSpace()]
        if model.canRenameSelectedMeeting {
            let rename = ActionButton(title: "Edit title") { self.requestMeetingRename() }
            rename.bezelStyle = .rounded
            headerItems.append(rename)
        }
        headerItems.append(export)
        if model.canDeleteSelectedMeeting {
            let delete = ActionButton(title: "Delete") { self.confirmDeleteSelectedMeeting() }
            delete.isBordered = false
            delete.font = .systemFont(ofSize: 11, weight: .medium)
            delete.contentTintColor = PesuTheme.coral
            headerItems.append(delete)
        }
        let header = horizontal(headerItems, spacing: 10)

        let document = vertical([], spacing: 0)
        document.addArrangedSubview(kicker(model.selectedMeeting.startedAt.formatted(date: .complete, time: .shortened).uppercased()))
        document.addArrangedSubview(label(model.selectedMeeting.title, size: usesCompactLayout ? 42 : 56, weight: .semibold, serif: true, lines: 2))
        let participants = label(model.selectedMeeting.participants.isEmpty ? "Recorded locally on this Mac" : model.selectedMeeting.participants.joined(separator: ", "), size: 11, color: PesuTheme.muted)
        document.addArrangedSubview(participants)
        document.setCustomSpacing(8, after: document.arrangedSubviews[0])
        document.setCustomSpacing(8, after: document.arrangedSubviews[1])
        document.addArrangedSubview(sectionHeading("IN BRIEF"))
        document.setCustomSpacing(42, after: participants)
        let brief = label(model.selectedMeeting.summary, size: 21, weight: .medium, serif: true, lines: 0)
        document.addArrangedSubview(brief)
        var lastBeforeDecisions: NSView = brief
        if model.canRenameSelectedMeeting {
            let buildCard = makeDaytonaBuildCard()
            document.addArrangedSubview(buildCard)
            buildCard.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true
            document.setCustomSpacing(28, after: brief)
            lastBeforeDecisions = buildCard
        }
        if model.isDecisionsEnabled {
            document.addArrangedSubview(sectionHeading("DECISIONS"))
            document.setCustomSpacing(42, after: lastBeforeDecisions)
            if model.selectedMeeting.decisions.isEmpty {
                document.addArrangedSubview(label("No explicit decisions were captured in this recording.", size: 11, color: PesuTheme.muted))
            } else {
                for decision in model.selectedMeeting.decisions { document.addArrangedSubview(decisionRow(decision)) }
            }
        }
        let lastBeforeTranscript = document.arrangedSubviews.last
        document.addArrangedSubview(sectionHeading("TRANSCRIPT"))
        if let lastBeforeTranscript {
            document.setCustomSpacing(42, after: lastBeforeTranscript)
        }
        if model.selectedMeeting.transcript.isEmpty {
            document.addArrangedSubview(label("Transcript processing has not completed.", size: 11, color: PesuTheme.muted))
        } else {
            for segment in model.selectedMeeting.transcript { document.addArrangedSubview(transcriptRow(segment)) }
        }

        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let docContainer = FlippedView(); docContainer.addSubview(document); scroll.documentView = docContainer
        document.translatesAutoresizingMaskIntoConstraints = false; docContainer.translatesAutoresizingMaskIntoConstraints = false
        let documentInset: CGFloat = usesCompactLayout ? 36 : 72
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor, constant: documentInset), document.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor, constant: -documentInset), document.topAnchor.constraint(equalTo: docContainer.topAnchor, constant: 52), document.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor, constant: -60),
            docContainer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        [header, scroll].forEach { page.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: page.topAnchor, constant: 21),
            header.heightAnchor.constraint(equalToConstant: 32),
            scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: page.topAnchor, constant: 62),
            scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor)
        ])
        return page
    }

    private func makeDaytonaBuildCard() -> NSView {
        let card = NSView()
        card.setBackground(PesuTheme.sidebar, cornerRadius: 18)
        let title = label("Turn this conversation into working software", size: 16, weight: .semibold, serif: true, lines: 2)
        let detail = label(
            "Review what will be shared, then Pēsu will build it with Codex in an isolated Daytona workspace.",
            size: 11,
            color: PesuTheme.muted,
            lines: 3
        )
        let copy = vertical([kicker("DAYTONA"), title, detail], spacing: 6)
        let build = ActionButton(title: "Build from this meeting") { [weak self] in
            self?.presentDaytonaWorkspace()
        }
        build.isBordered = false
        build.font = .systemFont(ofSize: 11, weight: .bold)
        build.contentTintColor = .white
        build.setBackground(PesuTheme.ink, cornerRadius: 18)
        build.translatesAutoresizingMaskIntoConstraints = false
        let content = horizontal([copy, flexibleSpace(), build], spacing: 18)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 17),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),
            build.widthAnchor.constraint(equalToConstant: 184),
            build.heightAnchor.constraint(equalToConstant: 38)
        ])
        return card
    }

    private func presentDaytonaWorkspace() {
        guard let window, workspaceSheetController == nil, model.canRenameSelectedMeeting else { return }
        model.refreshBuildCredentialStatus()
        let readiness = BuildCredentialReadiness.evaluate(
            daytona: model.daytonaCredentialAvailability,
            openAI: model.openAICredentialAvailability
        )
        guard readiness == .ready else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            switch readiness {
            case .ready:
                return
            case .keychainUnavailable:
                alert.messageText = "macOS Keychain is unavailable"
                alert.informativeText = "Unlock this Mac, then try Build from this meeting again. Pēsu cannot access either API key while Keychain is unavailable."
                alert.addButton(withTitle: "OK")
            case let .missing(providers):
                alert.messageText = providers.count == 1
                    ? "Add your \(providers[0]) API key first"
                    : "Add your Daytona and OpenAI API keys first"
                alert.informativeText = "Pēsu stores each key securely in macOS Keychain and retrieves its value only after you approve Build from this meeting."
                alert.addButton(withTitle: "Open Settings")
            }
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard case .missing = readiness, response == .alertFirstButtonReturn else { return }
                self?.model.showSettings()
            }
            return
        }
        let controller = DaytonaWorkspaceSheetController(
            meeting: model.selectedMeeting,
            hostWindow: window
        ) { [weak self] in
            self?.workspaceSheetController = nil
        }
        workspaceSheetController = controller
        controller.present()
    }

    private func decisionRow(_ decision: Decision) -> NSView {
        let row = horizontal([
            label(decision.id, size: 17, weight: .bold, color: PesuTheme.coral),
            label(decision.text, size: 13, lines: 3)
        ], spacing: 15)
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        return row
    }

    private func transcriptRow(_ segment: TranscriptSegment) -> NSView {
        let row = horizontal([
            label(segment.timestamp, size: 10, color: PesuTheme.muted),
            label(segment.speaker, size: 11, weight: .bold),
            label(segment.text, size: 11, lines: 3)
        ], spacing: 14)
        row.edgeInsets = NSEdgeInsets(top: 13, left: 8, bottom: 13, right: 8)
        row.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 48).isActive = true
        row.arrangedSubviews[1].widthAnchor.constraint(equalToConstant: 70).isActive = true
        return row
    }

    private func sectionHeading(_ title: String) -> NSView {
        vertical([label(title, size: 10, weight: .bold), separator()], spacing: 9)
    }

    private func newRecordingButton() -> NSButton {
        let button = ActionButton(title: "New recording") { self.requestMeetingNameAndStart() }
        button.font = .systemFont(ofSize: 11, weight: .bold); button.bezelStyle = .rounded
        return button
    }

    private func requestMeetingNameAndStart() {
        presentMeetingTitlePrompt(
            message: "Name this meeting",
            detail: "Add a name before Pēsu starts recording.",
            initialValue: "",
            confirmTitle: "Start recording"
        ) { [weak self] title in
            guard let self, let title else { return }
            self.model.startRecording(named: title)
        }
    }

    private func requestMeetingRename() {
        presentMeetingTitlePrompt(
            message: "Edit meeting name",
            detail: "This changes the name of the recording saved on this Mac.",
            initialValue: model.selectedMeeting.title,
            confirmTitle: "Save"
        ) { [weak self] title in
            guard let self, let title else { return }
            do {
                try self.model.renameSelectedMeeting(to: title)
            } catch {
                self.showAlert(message: "Could not update the meeting name", detail: error.localizedDescription)
            }
        }
    }

    private func presentMeetingTitlePrompt(
        message: String,
        detail: String,
        initialValue: String,
        confirmTitle: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let window, titleSheet == nil else { completion(nil); return }
        let sheet = KeyableSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 310),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        sheet.isOpaque = false
        sheet.backgroundColor = .clear
        sheet.hasShadow = true
        sheet.appearance = NSAppearance(named: .aqua)

        let card = NSView()
        card.setBackground(PesuTheme.paper, cornerRadius: 24)
        let eyebrow = kicker(initialValue.isEmpty ? "NEW RECORDING" : "MEETING")
        let heading = label(message, size: 27, weight: .semibold, lines: 2)
        let explanation = label(detail, size: 12, color: PesuTheme.muted, lines: 2)
        let validation = label("Enter a meeting name to continue.", size: 10, weight: .medium, color: PesuTheme.coral)
        validation.isHidden = true

        let field = ActionTextField(string: initialValue) {}
        field.placeholderString = "Meeting name"
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.setAccessibilityLabel("Meeting name")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let closeSheet: (String?) -> Void = { [weak self, weak sheet] value in
            guard let sheet else { return }
            window.endSheet(sheet)
            self?.titleSheet = nil
            completion(value)
        }
        let submit: () -> Void = { [weak field, weak validation] in
            guard let field else { return }
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                validation?.isHidden = false
                NSSound.beep()
                return
            }
            closeSheet(title)
        }
        field.actionHandler = submit

        let cancel = ActionButton(title: "Cancel") { closeSheet(nil) }
        cancel.isBordered = false
        cancel.font = .systemFont(ofSize: 12, weight: .medium)
        cancel.setBackground(PesuTheme.line.withAlphaComponent(0.5), cornerRadius: 18)
        cancel.keyEquivalent = "\u{1b}"
        let confirm = ActionButton(title: confirmTitle, handler: submit)
        confirm.isBordered = false
        confirm.font = .systemFont(ofSize: 12, weight: .bold)
        confirm.contentTintColor = .white
        confirm.setBackground(PesuTheme.ink, cornerRadius: 18)
        confirm.keyEquivalent = "\r"
        let actions = horizontal([cancel, confirm], spacing: 10)
        NSLayoutConstraint.activate([
            cancel.widthAnchor.constraint(equalToConstant: 108),
            confirm.widthAnchor.constraint(equalToConstant: 150),
            cancel.heightAnchor.constraint(equalToConstant: 38),
            confirm.heightAnchor.constraint(equalToConstant: 38)
        ])

        let content = vertical([eyebrow, heading, explanation, field, validation, actions], spacing: 10)
        validation.isHidden = true
        content.setCustomSpacing(7, after: eyebrow)
        content.setCustomSpacing(8, after: heading)
        content.setCustomSpacing(22, after: explanation)
        content.setCustomSpacing(8, after: field)
        content.setCustomSpacing(18, after: validation)
        actions.alignment = .centerY
        card.addSubview(content)
        sheet.contentView = card
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 38),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -38),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 32),
            field.widthAnchor.constraint(equalTo: content.widthAnchor),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -28)
        ])
        titleSheet = sheet
        window.beginSheet(sheet)
        DispatchQueue.main.async {
            sheet.makeFirstResponder(field)
        }
    }

    private func makeExportButton() -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.addItem(withTitle: "Export")
        button.item(at: 0)?.isEnabled = false
        let markdown = NSMenuItem(title: "Save as Markdown…", action: #selector(saveSelectedMeetingAsMarkdown(_:)), keyEquivalent: "")
        markdown.target = self
        let email = NSMenuItem(title: "Send by Email…", action: #selector(emailSelectedMeeting(_:)), keyEquivalent: "")
        email.target = self
        button.menu?.addItem(markdown)
        button.menu?.addItem(email)
        button.setAccessibilityLabel("Export meeting")
        return button
    }

    @objc private func saveSelectedMeetingAsMarkdown(_ sender: Any?) {
        guard let window, model.selectedMeeting != .empty else { return }
        let panel = NSSavePanel()
        panel.title = "Export Meeting"
        panel.nameFieldStringValue = MeetingMarkdownExporter.fileName(for: model.selectedMeeting)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try MeetingMarkdownExporter.markdown(
                    for: self.model.selectedMeeting,
                    includeDecisions: self.model.isDecisionsEnabled
                )
                    .write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.showAlert(message: "Could not export the meeting", detail: error.localizedDescription)
            }
        }
    }

    @objc private func emailSelectedMeeting(_ sender: Any?) {
        guard model.selectedMeeting != .empty,
              let email = NSSharingService(named: .composeEmail) else {
            showAlert(message: "Email is unavailable", detail: "Set up an email account in Mail and try again.")
            return
        }
        email.subject = model.selectedMeeting.title
        email.perform(withItems: [MeetingMarkdownExporter.markdown(
            for: model.selectedMeeting,
            includeDecisions: model.isDecisionsEnabled
        )])
    }

    private func confirmDeleteSelectedMeeting() {
        guard let window, model.canDeleteSelectedMeeting else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this meeting?"
        alert.informativeText = "The note, transcript and its local audio files will be permanently removed from this Mac."
        alert.addButton(withTitle: "Delete Meeting")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.model.deleteSelectedMeeting()
            } catch {
                self.showAlert(message: "Could not delete the meeting", detail: error.localizedDescription)
            }
        }
    }

    private func showAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        guard model.screen != .recording else { return }
        sidebarItem.animator().isCollapsed.toggle()
    }

}

extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.pesuSidebar, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.pesuSidebar]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == .pesuSidebar else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Sidebar"
        item.paletteLabel = "Show or hide the sidebar"
        item.toolTip = "Show or hide the sidebar"
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Show or hide sidebar")
        item.target = self
        item.action = #selector(toggleSidebar(_:))
        sidebarToolbarItem = item
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let pesuSidebar = NSToolbarItem.Identifier("PesuSidebar")
}

extension MainWindowController: NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let compact = frameSize.width < 1_020
        if compact != usesCompactLayout {
            usesCompactLayout = compact
            needsFullPageRender = true
            scheduleRender()
        }
        if frameSize.width < 860, !sidebarItem.isCollapsed {
            sidebarItem.isCollapsed = true
        }
        return frameSize
    }
}
