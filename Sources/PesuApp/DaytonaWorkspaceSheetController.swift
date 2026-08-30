import AppKit

@MainActor
final class DaytonaWorkspaceSheetController {
    private let meeting: Meeting
    private let hostWindow: NSWindow
    private let onProcessPhase: (AppProcessPhase) -> Void
    private let onDismiss: () -> Void
    private let client = DaytonaWorkspaceClient()

    private let sheet: KeyableSheetWindow
    private let actionPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let instructionView = NSTextView(frame: .zero)
    private let validationLabel = label("Choose a decision or describe what to build.", size: 10, weight: .medium, color: PesuTheme.coral)
    private let configurationView = NSView()
    private let progressView = NSView()
    private let statusLabel = label("Preparing your workspace…", size: 20, weight: .semibold, serif: true, lines: 2)
    private let activityView = NSTextView(frame: .zero)
    private let openButton = ActionButton(title: "Open live result") {}
    private let retryButton = ActionButton(title: "Retry") {}

    private var workspaceTask: Task<Void, Never>?
    private var previewURL: URL?
    private var didDismiss = false

    init(
        meeting: Meeting,
        hostWindow: NSWindow,
        onProcessPhase: @escaping (AppProcessPhase) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.meeting = meeting
        self.hostWindow = hostWindow
        self.onProcessPhase = onProcessPhase
        self.onDismiss = onDismiss
        sheet = KeyableSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 610),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureSheet()
    }

    func present() {
        hostWindow.beginSheet(sheet)
    }

    private func configureSheet() {
        sheet.isOpaque = false
        sheet.backgroundColor = .clear
        sheet.hasShadow = true
        sheet.appearance = NSAppearance(named: .aqua)

        let card = NSView()
        card.setBackground(PesuTheme.paper, cornerRadius: 24)
        sheet.contentView = card

        configureActionPicker()
        configureInstructionView()
        configureConfigurationView()
        configureProgressView()

        card.addSubview(configurationView)
        card.addSubview(progressView)
        configurationView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true
        NSLayoutConstraint.activate([
            configurationView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
            configurationView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),
            configurationView.topAnchor.constraint(equalTo: card.topAnchor, constant: 34),
            configurationView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -32),
            progressView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
            progressView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),
            progressView.topAnchor.constraint(equalTo: card.topAnchor, constant: 34),
            progressView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -32)
        ])
    }

    private func configureActionPicker() {
        if meeting.decisions.isEmpty {
            actionPicker.addItem(withTitle: "Describe what to build below")
            actionPicker.itemArray.last?.representedObject = ""
        } else {
            for decision in meeting.decisions.prefix(8) {
                actionPicker.addItem(withTitle: decision.text)
                actionPicker.itemArray.last?.representedObject = decision.text
            }
            actionPicker.menu?.addItem(.separator())
            actionPicker.addItem(withTitle: "Custom build instruction…")
            actionPicker.itemArray.last?.representedObject = ""
        }
        actionPicker.bezelStyle = .rounded
        actionPicker.font = .systemFont(ofSize: 12, weight: .medium)
        actionPicker.setAccessibilityLabel("Meeting action to build")
        actionPicker.translatesAutoresizingMaskIntoConstraints = false
        actionPicker.heightAnchor.constraint(equalToConstant: 38).isActive = true
    }

    private func configureInstructionView() {
        instructionView.font = .systemFont(ofSize: 13)
        instructionView.textColor = PesuTheme.ink
        instructionView.backgroundColor = .white.withAlphaComponent(0.65)
        instructionView.isRichText = false
        instructionView.isAutomaticQuoteSubstitutionEnabled = false
        instructionView.setAccessibilityLabel("Optional build instructions")
        instructionView.textContainerInset = NSSize(width: 10, height: 9)
    }

    private func configureConfigurationView() {
        let heading = label("Build from this meeting", size: 29, weight: .semibold, serif: true, lines: 2)
        let explanation = label(
            "Pēsu will create an isolated Daytona workspace and ask Codex to turn the selected action into a small working prototype.",
            size: 12,
            color: PesuTheme.muted,
            lines: 3
        )
        let chooseHeading = label("WHAT SHOULD CODEX BUILD?", size: 10, weight: .bold)
        let instructionHeading = label("OPTIONAL DIRECTION", size: 10, weight: .bold)

        let instructionScroll = NSScrollView()
        instructionScroll.documentView = instructionView
        instructionScroll.hasVerticalScroller = true
        instructionScroll.borderType = .bezelBorder
        instructionScroll.translatesAutoresizingMaskIntoConstraints = false
        instructionScroll.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let privacyCard = NSView()
        privacyCard.setBackground(PesuTheme.sidebar, cornerRadius: 14)
        let privacyHeading = label("Content Pēsu will send after you confirm", size: 11, weight: .bold)
        let privacyText = NSTextView(frame: .zero)
        privacyText.string = sharedMeetingContextDescription()
        privacyText.isEditable = false
        privacyText.isSelectable = true
        privacyText.isRichText = false
        privacyText.font = .systemFont(ofSize: 10.5)
        privacyText.textColor = PesuTheme.muted
        privacyText.backgroundColor = .clear
        privacyText.textContainerInset = .zero
        let privacyScroll = NSScrollView()
        privacyScroll.documentView = privacyText
        privacyScroll.hasVerticalScroller = true
        privacyScroll.drawsBackground = false
        privacyScroll.borderType = .noBorder
        privacyScroll.translatesAutoresizingMaskIntoConstraints = false
        privacyScroll.heightAnchor.constraint(equalToConstant: 74).isActive = true
        let staysLocal = label(
            "Not shared: audio, participants, file paths, or the full transcript.",
            size: 10,
            weight: .medium,
            color: PesuTheme.ink,
            lines: 2
        )
        let privacyStack = vertical([privacyHeading, privacyScroll, staysLocal], spacing: 6)
        privacyCard.addSubview(privacyStack)
        NSLayoutConstraint.activate([
            privacyStack.leadingAnchor.constraint(equalTo: privacyCard.leadingAnchor, constant: 16),
            privacyStack.trailingAnchor.constraint(equalTo: privacyCard.trailingAnchor, constant: -16),
            privacyStack.topAnchor.constraint(equalTo: privacyCard.topAnchor, constant: 13),
            privacyStack.bottomAnchor.constraint(equalTo: privacyCard.bottomAnchor, constant: -13),
            privacyScroll.widthAnchor.constraint(equalTo: privacyStack.widthAnchor)
        ])

        validationLabel.isHidden = true
        let cancel = ActionButton(title: "Cancel") { [weak self] in self?.dismiss() }
        styleSecondary(cancel, width: 106)
        cancel.keyEquivalent = "\u{1b}"
        let create = ActionButton(title: "Create Daytona workspace") { [weak self] in self?.startBuild() }
        stylePrimary(create, width: 205)
        create.keyEquivalent = "\r"
        let actions = horizontal([cancel, create], spacing: 10)

        let content = vertical([
            kicker("DAYTONA + CODEX"), heading, explanation,
            chooseHeading, actionPicker, instructionHeading, instructionScroll,
            privacyCard, validationLabel, actions
        ], spacing: 10)
        content.setCustomSpacing(7, after: content.arrangedSubviews[0])
        content.setCustomSpacing(8, after: heading)
        content.setCustomSpacing(24, after: explanation)
        content.setCustomSpacing(18, after: actionPicker)
        content.setCustomSpacing(18, after: instructionScroll)
        content.setCustomSpacing(14, after: privacyCard)
        actions.alignment = .centerY
        configurationView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: configurationView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: configurationView.trailingAnchor),
            content.topAnchor.constraint(equalTo: configurationView.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: configurationView.bottomAnchor),
            actionPicker.widthAnchor.constraint(equalTo: content.widthAnchor),
            instructionScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            privacyCard.widthAnchor.constraint(equalTo: content.widthAnchor),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
    }

    private func configureProgressView() {
        let explanation = label(
            "These updates come from the isolated workspace. Pēsu never sends the meeting audio or full transcript.",
            size: 12,
            color: PesuTheme.muted,
            lines: 3
        )
        activityView.isEditable = false
        activityView.isSelectable = true
        activityView.isRichText = false
        activityView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        activityView.textColor = NSColor(white: 0.88, alpha: 1)
        activityView.backgroundColor = PesuTheme.dark
        activityView.textContainerInset = NSSize(width: 12, height: 12)

        let activityScroll = NSScrollView()
        activityScroll.documentView = activityView
        activityScroll.hasVerticalScroller = true
        activityScroll.borderType = .noBorder
        activityScroll.setBackground(PesuTheme.dark, cornerRadius: 12)
        activityScroll.translatesAutoresizingMaskIntoConstraints = false
        activityScroll.heightAnchor.constraint(equalToConstant: 280).isActive = true

        let close = ActionButton(title: "Close") { [weak self] in self?.dismiss() }
        styleSecondary(close, width: 96)
        close.keyEquivalent = "\u{1b}"
        retryButton.actionHandler = { [weak self] in self?.startBuild() }
        styleSecondary(retryButton, width: 96)
        retryButton.isHidden = true
        openButton.actionHandler = { [weak self] in
            guard let url = self?.previewURL else { return }
            NSWorkspace.shared.open(url)
        }
        stylePrimary(openButton, width: 150)
        openButton.isHidden = true
        let actions = horizontal([close, retryButton, openButton], spacing: 10)

        let content = vertical([
            kicker("BUILDING IN DAYTONA"), statusLabel, explanation, activityScroll, actions
        ], spacing: 11)
        content.setCustomSpacing(7, after: content.arrangedSubviews[0])
        content.setCustomSpacing(8, after: statusLabel)
        content.setCustomSpacing(22, after: explanation)
        content.setCustomSpacing(18, after: activityScroll)
        progressView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: progressView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: progressView.trailingAnchor),
            content.topAnchor.constraint(equalTo: progressView.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: progressView.bottomAnchor),
            activityScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
    }

    private func startBuild() {
        let selectedAction = actionPicker.selectedItem?.representedObject as? String ?? ""
        let instruction = instructionView.string
        let context: DaytonaWorkspaceContext
        do {
            context = try DaytonaWorkspaceContext.make(
                meeting: meeting,
                selectedAction: selectedAction,
                userInstruction: instruction
            )
        } catch {
            validationLabel.stringValue = error.localizedDescription
            validationLabel.isHidden = false
            NSSound.beep()
            return
        }

        validationLabel.isHidden = true
        configurationView.isHidden = true
        progressView.isHidden = false
        statusLabel.stringValue = "Preparing your workspace…"
        activityView.string = ""
        previewURL = nil
        openButton.isHidden = true
        retryButton.isHidden = true
        workspaceTask?.cancel()
        onProcessPhase(.daytonaStarting)
        workspaceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await client.createWorkspace(context: context) { [weak self] event in
                    self?.receive(event)
                }
                previewURL = url
                openButton.isHidden = false
            } catch is CancellationError {
                return
            } catch {
                statusLabel.stringValue = "Workspace creation failed"
                appendActivity("Error: \(error.localizedDescription)")
                retryButton.isHidden = false
                onProcessPhase(.error)
            }
        }
    }

    private func receive(_ event: DaytonaWorkspaceEvent) {
        statusLabel.stringValue = event.message
        appendActivity(event.message)
        onProcessPhase(event.type.appProcessPhase)
        if event.type == .ready {
            previewURL = event.previewURL
            openButton.isHidden = previewURL == nil
            retryButton.isHidden = true
        }
    }

    private func appendActivity(_ message: String) {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let prefix = activityView.string.isEmpty ? "" : "\n"
        activityView.textStorage?.append(NSAttributedString(string: prefix + clean))
        activityView.scrollToEndOfDocument(nil)
    }

    private func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        workspaceTask?.cancel()
        hostWindow.endSheet(sheet)
        onProcessPhase(.idle)
        onDismiss()
    }

    private func sharedMeetingContextDescription() -> String {
        var transcriptByID: [String: String] = [:]
        for segment in meeting.transcript where transcriptByID[segment.id] == nil {
            transcriptByID[segment.id] = segment.text
        }
        var lines = [
            "Title: \(String(meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))",
            "Brief: \(String(meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000)))"
        ]
        for decision in meeting.decisions.prefix(8) {
            lines.append("Decision \(decision.id): \(String(decision.text.prefix(500)))")
            if let evidence = transcriptByID[decision.evidenceSegmentID], !evidence.isEmpty {
                lines.append("Linked evidence: \(String(evidence.prefix(500)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func stylePrimary(_ button: NSButton, width: CGFloat) {
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .bold)
        button.contentTintColor = .white
        button.setBackground(PesuTheme.ink, cornerRadius: 18)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private func styleSecondary(_ button: NSButton, width: CGFloat) {
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.setBackground(PesuTheme.line.withAlphaComponent(0.5), cornerRadius: 18)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])
    }
}
