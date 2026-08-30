import Foundation

@MainActor
final class AppModel {
    var onChange: ((AppModelChange) -> Void)?
    var screen: AppScreen = .present
    var meetings: [Meeting] = []
    var calendarMeetings: [Meeting] = []
    var selectedMeeting: Meeting = .empty
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var recordingTitle = ""
    var captureStatus = "Ready"
    var speechStatus = "Live transcription ready"
    var liveTranscriptSegments: [TranscriptSegment] = []
    var liveTranscriptDraft = ""
    var microphones: [MicrophoneOption] = AppleAudioCapture.availableMicrophones()
    var selectedMicrophoneID = MicrophoneOption.systemDefaultID
    var speechModelStatus = "Checking local model…"
    var summaryModelStatus = "Checking local model…"
    var storeStatus = "Local database ready"
    var calendarStatus = "Not connected"
    var calendarDetail = "Connect Apple Calendar to show your meetings in Pēsu."
    var calendarSources: [CalendarSourceOption] = []
    var duplicateNotice = ""
    var isCalendarSyncing = false
    var isStatsTabEnabled = true
    var isDecisionsEnabled = true
    var arePetsEnabled = true
    var selectedPet: PetChoice = .corgi
    var processPhase: AppProcessPhase = .idle
    var hasDaytonaAPIKey = false
    var daytonaCredentialStatus = "Not configured"
    var daytonaCredentialAvailability: APIKeyAvailability = .missing
    var hasOpenAIAPIKey = false
    var openAICredentialStatus = "Not configured"
    var openAICredentialAvailability: APIKeyAvailability = .missing
    var selectedBuildAIProvider: BuildAIProvider = .openAI
    var azureOpenAIEndpoint = ""
    var azureOpenAIDeployment = ""
    var hasAzureOpenAIAPIKey = false
    var azureOpenAICredentialStatus = "Not configured"
    var azureOpenAICredentialAvailability: APIKeyAvailability = .missing

    private var store: MeetingStore?
    private let capture = AppleAudioCapture()
    private let intelligence = AppleIntelligence()
    private let calendar = AppleCalendarService()
    private let daytonaCredentials = APIKeyCredentialStore(service: APIKeyCredentialStore.daytonaService)
    private let openAICredentials = APIKeyCredentialStore(service: APIKeyCredentialStore.openAIService)
    private let azureOpenAICredentials = APIKeyCredentialStore(service: APIKeyCredentialStore.azureOpenAIService)
    private var recordingTask: Task<Void, Never>?
    private var captureFiles: CaptureFiles?
    private let futureRangeKey = "pesu.calendar.futureRangeEnd"
    private let calendarSelectionKey = "pesu.calendar.sourceSelections"
    private let microphoneSelectionKey = "pesu.recording.microphone"
    private let statsTabEnabledKey = "pesu.sidebar.statsEnabled"
    private let decisionsEnabledKey = "pesu.sidebar.decisionsEnabled"
    private var calendarSelections: [String: Bool] = [:]
    private var futureSyncEnd = CalendarSyncWindow.initialFutureEnd(relativeTo: Date())

    private var allMeetings: [Meeting] { meetings + calendarMeetings }

    var pastMeetings: [Meeting] {
        let today = Calendar.current.startOfDay(for: Date())
        return allMeetings.filter { $0.startedAt < today }.sorted { $0.startedAt > $1.startedAt }
    }

    var presentMeetings: [Meeting] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return allMeetings.filter { $0.startedAt >= today && $0.startedAt < tomorrow }.sorted { $0.startedAt < $1.startedAt }
    }

    var futureMeetings: [Meeting] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return allMeetings.filter { $0.startedAt >= tomorrow }.sorted { $0.startedAt < $1.startedAt }
    }

    var presentDuplicateGroups: [DuplicateMeetingGroup] {
        MeetingDuplicateDetector.groups(in: presentMeetings)
    }

    var futureDuplicateGroups: [DuplicateMeetingGroup] {
        MeetingDuplicateDetector.groups(in: futureMeetings)
    }

    var meetingStats: MeetingStatsSnapshot {
        MeetingStatsSnapshot.calculate(from: allMeetings)
    }

    var calendarButtonTitle: String {
        if isCalendarSyncing { return "Syncing…" }
        switch calendar.connectionState {
        case .connected: return "Sync now"
        case .notConnected: return "Connect Apple Calendar"
        case .denied: return "Access disabled"
        }
    }

    var isCalendarConnected: Bool { calendar.connectionState == .connected }
    var canRequestCalendarAccess: Bool { calendar.connectionState != .denied }
    var enabledCalendarCount: Int { calendarSources.filter(\.isEnabled).count }
    var enabledCalendarIdentifiers: Set<String> {
        Set(calendarSources.filter(\.isEnabled).map(\.id))
    }
    var futureRangeDescription: String {
        "Loaded through \(futureSyncEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
    var selectedMicrophone: MicrophoneOption {
        microphones.first(where: { $0.id == selectedMicrophoneID }) ?? microphones[0]
    }
    var canRenameSelectedMeeting: Bool {
        selectedMeeting.systemAudioPath != nil || selectedMeeting.microphonePath != nil
    }
    var canDeleteSelectedMeeting: Bool {
        canRenameSelectedMeeting && meetings.contains { $0.id == selectedMeeting.id }
    }
    var liveTranscriptDisplay: String {
        let finalText = liveTranscriptSegments
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "  ")
        let combined = [finalText, liveTranscriptDraft]
            .filter { !$0.isEmpty }
            .joined(separator: finalText.isEmpty ? "" : " ")
        guard !combined.isEmpty else { return "Start speaking and your live transcript will appear here." }
        return String(combined.suffix(900))
    }

    var petActivity: PetActivity {
        PetActivityMapper.activity(for: processPhase)
    }

    init() {
        let petPreferences = PetPreferences.load()
        arePetsEnabled = petPreferences.isEnabled
        selectedPet = petPreferences.selectedPet
        selectedBuildAIProvider = BuildAIProviderSettings.provider()
        azureOpenAIEndpoint = UserDefaults.standard.string(forKey: BuildAIProviderSettings.azureEndpointKey) ?? ""
        azureOpenAIDeployment = UserDefaults.standard.string(forKey: BuildAIProviderSettings.azureDeploymentKey) ?? ""
        if UserDefaults.standard.object(forKey: statsTabEnabledKey) != nil {
            isStatsTabEnabled = UserDefaults.standard.bool(forKey: statsTabEnabledKey)
        }
        if UserDefaults.standard.object(forKey: decisionsEnabledKey) != nil {
            isDecisionsEnabled = UserDefaults.standard.bool(forKey: decisionsEnabledKey)
        }
        let savedMicrophoneID = UserDefaults.standard.string(forKey: microphoneSelectionKey)
        if let savedMicrophoneID, microphones.contains(where: { $0.id == savedMicrophoneID }) {
            selectedMicrophoneID = savedMicrophoneID
        }
        calendarSelections = UserDefaults.standard.dictionary(forKey: calendarSelectionKey)?
            .compactMapValues { $0 as? Bool } ?? [:]
        if let savedEnd = UserDefaults.standard.object(forKey: futureRangeKey) as? Date, savedEnd > futureSyncEnd {
            futureSyncEnd = savedEnd
        }
        do {
            let store = try MeetingStore()
            self.store = store
            meetings = try store.fetchMeetings().map { meeting in
                let normalized = normalizedMeeting(meeting)
                if normalized.summary != meeting.summary || normalized.decisions != meeting.decisions {
                    try? store.updateNotes(
                        forMeetingID: normalized.id,
                        summary: normalized.summary,
                        decisions: normalized.decisions
                    )
                }
                return normalized
            }
            selectedMeeting = meetings.first ?? .empty
        } catch {
            store = nil
            meetings = []
            storeStatus = "Local database unavailable: \(error.localizedDescription)"
        }

        updateCalendarCopy()
        refreshBuildCredentialStatus()
        refreshLocalModelStatus()
        if calendar.connectionState == .connected { refreshCalendar() }
    }

    func showPresent() { processPhase = .idle; screen = .present; notify() }
    func showPast() { processPhase = .idle; screen = .past; notify() }
    func showFuture() { processPhase = .idle; screen = .future; notify() }
    func showStats() {
        guard isStatsTabEnabled else { return }
        processPhase = .idle
        screen = .stats
        notify()
    }
    func showSettings() {
        refreshMicrophones()
        refreshBuildCredentialStatus()
        refreshLocalModelStatus()
        processPhase = .idle
        screen = .settings
        notify()
    }

    func saveDaytonaAPIKey(_ key: String) throws {
        try daytonaCredentials.saveAPIKey(key)
        refreshBuildCredentialStatus()
        notify()
    }

    func removeDaytonaAPIKey() throws {
        try daytonaCredentials.deleteAPIKey()
        refreshBuildCredentialStatus()
        notify()
    }

    func saveOpenAIAPIKey(_ key: String) throws {
        try openAICredentials.saveAPIKey(key)
        refreshBuildCredentialStatus()
        notify()
    }

    func removeOpenAIAPIKey() throws {
        try openAICredentials.deleteAPIKey()
        refreshBuildCredentialStatus()
        notify()
    }

    func setBuildAIProvider(_ provider: BuildAIProvider) {
        guard selectedBuildAIProvider != provider else { return }
        selectedBuildAIProvider = provider
        BuildAIProviderSettings.saveProvider(provider)
    }

    func buildAIProviderSelection() throws -> BuildAIProviderSelection {
        switch selectedBuildAIProvider {
        case .openAI:
            return .openAI
        case .azureOpenAI:
            return .azureOpenAI(try AzureOpenAIConfiguration(
                endpoint: azureOpenAIEndpoint,
                deployment: azureOpenAIDeployment
            ))
        }
    }

    func saveAzureOpenAISettings(
        endpoint: String,
        deployment: String,
        apiKey: String
    ) throws -> AzureOpenAIConfiguration {
        let configuration = try AzureOpenAIConfiguration(endpoint: endpoint, deployment: deployment)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            try azureOpenAICredentials.saveAPIKey(trimmedKey)
        } else if !hasAzureOpenAIAPIKey {
            throw APIKeyCredentialStore.StoreError.emptyAPIKey
        }
        BuildAIProviderSettings.saveAzureConfiguration(configuration)
        azureOpenAIEndpoint = configuration.endpoint
        azureOpenAIDeployment = configuration.deployment
        refreshBuildCredentialStatus()
        return configuration
    }

    func removeAzureOpenAIAPIKey() throws {
        try azureOpenAICredentials.deleteAPIKey()
        refreshBuildCredentialStatus()
        notify()
    }

    func setStatsTabEnabled(_ enabled: Bool) {
        guard isStatsTabEnabled != enabled else { return }
        isStatsTabEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: statsTabEnabledKey)
        if !enabled, screen == .stats { screen = .settings }
        notify()
    }

    func setDecisionsEnabled(_ enabled: Bool) {
        guard isDecisionsEnabled != enabled else { return }
        isDecisionsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: decisionsEnabledKey)
        notify()
    }

    func setPetsEnabled(_ enabled: Bool) {
        guard arePetsEnabled != enabled else { return }
        arePetsEnabled = enabled
        PetPreferences.setEnabled(enabled)
        notify(.petPresentation)
    }

    func selectPet(_ pet: PetChoice) {
        guard selectedPet != pet else { return }
        selectedPet = pet
        PetPreferences.setSelectedPet(pet)
        notify(.petPresentation)
    }

    func observeDaytonaProcess(_ phase: AppProcessPhase) {
        guard processPhase != phase else { return }
        processPhase = phase
        notify(.process)
    }

    func selectMicrophone(_ id: String) {
        guard !isRecording, microphones.contains(where: { $0.id == id }) else { return }
        selectedMicrophoneID = id
        UserDefaults.standard.set(id, forKey: microphoneSelectionKey)
        notify()
    }

    func refreshAudioDevices() {
        guard !isRecording else { return }
        refreshMicrophones()
        notify()
    }

    func connectOrRefreshCalendar() {
        guard !isCalendarSyncing else { return }
        if calendar.connectionState == .connected {
            refreshCalendar()
            return
        }

        isCalendarSyncing = true
        calendarStatus = "Connecting…"
        calendarDetail = "macOS will ask you to allow Pēsu to read calendar events."
        notify()

        Task {
            do {
                let granted = try await calendar.requestAccess()
                if granted { await loadCalendarMeetings() }
                else {
                    isCalendarSyncing = false
                    updateCalendarCopy()
                    notify()
                }
            } catch {
                isCalendarSyncing = false
                calendarStatus = "Could not connect"
                calendarDetail = error.localizedDescription
                notify()
            }
        }
    }

    func refreshCalendar() {
        guard calendar.connectionState == .connected, !isCalendarSyncing else {
            updateCalendarCopy()
            notify()
            return
        }
        isCalendarSyncing = true
        calendarStatus = "Syncing…"
        notify()
        Task { await loadCalendarMeetings() }
    }

    func loadLaterCalendarEvents() {
        guard calendar.connectionState == .connected, !isCalendarSyncing else { return }
        let start = futureSyncEnd
        let end = CalendarSyncWindow.extending(start)
        guard end > start else { return }

        isCalendarSyncing = true
        calendarStatus = "Loading later events…"
        notify()

        Task {
            let additional = await calendar.fetchMeetings(
                from: start,
                to: end,
                calendarIdentifiers: enabledCalendarIdentifiers
            )
            var merged = Dictionary(uniqueKeysWithValues: calendarMeetings.map { ($0.id, $0) })
            for meeting in additional { merged[meeting.id] = meeting }
            calendarMeetings = merged.values.sorted { $0.startedAt < $1.startedAt }
            futureSyncEnd = end
            UserDefaults.standard.set(end, forKey: futureRangeKey)
            isCalendarSyncing = false
            updateCalendarCopy()
            notify()
        }
    }

    func setCalendarSource(_ id: String, enabled: Bool) {
        guard let index = calendarSources.firstIndex(where: { $0.id == id }), !isCalendarSyncing else { return }
        calendarSources[index].isEnabled = enabled
        calendarSelections[id] = enabled
        UserDefaults.standard.set(calendarSelections, forKey: calendarSelectionKey)
        duplicateNotice = ""
        refreshCalendar()
    }

    func resolveDuplicates(in scope: DuplicateMeetingScope, strategy: DuplicateResolutionStrategy) {
        guard calendar.connectionState == .connected, !isCalendarSyncing else { return }
        let groups = scope == .present ? presentDuplicateGroups : futureDuplicateGroups
        guard !groups.isEmpty else { return }

        isCalendarSyncing = true
        duplicateNotice = strategy == .merge ? "Merging duplicate events…" : "Removing duplicate copies…"
        notify()

        Task {
            let result = await calendar.resolveDuplicateGroups(
                groups.map { $0.meetings.map(\.id) },
                strategy: strategy
            )
            await loadCalendarMeetings()

            let action = strategy == .merge ? "Merged" : "Removed"
            if result.groupsResolved == 0 {
                duplicateNotice = result.groupsSkipped > 0
                    ? "No duplicates changed. Some calendars do not allow editing."
                    : "No duplicate events needed changing."
            } else {
                duplicateNotice = "\(action) \(result.copiesRemoved) duplicate \(result.copiesRemoved == 1 ? "copy" : "copies") across \(result.groupsResolved) \(result.groupsResolved == 1 ? "meeting" : "meetings")."
                if result.groupsSkipped > 0 { duplicateNotice += " \(result.groupsSkipped) could not be edited." }
            }
            notify()
        }
    }

    func open(_ meeting: Meeting) {
        selectedMeeting = normalizedMeeting(meeting)
        processPhase = .idle
        screen = .summary
        notify()
    }

    func startRecording(named title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        recordingTitle = title
        screen = .recording
        isRecording = true
        recordingDuration = 0
        liveTranscriptSegments = []
        liveTranscriptDraft = ""
        speechStatus = "Preparing on-device Apple Speech…"
        captureStatus = "Preparing \(selectedMicrophone.name)…"
        processPhase = .meetingStarting
        notify()

        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let startedFiles = try await capture.start(
                    microphoneDeviceID: selectedMicrophone.captureDeviceID,
                    onTranscriptUpdate: { [weak self] snapshot in
                        Task { @MainActor in self?.applyLiveTranscript(snapshot) }
                    }
                )
                guard !Task.isCancelled else {
                    _ = await capture.stop()
                    return
                }
                captureFiles = startedFiles
                captureStatus = "Recording system audio + \(selectedMicrophone.name) locally"
                processPhase = liveTranscriptSegments.isEmpty
                    && liveTranscriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .listening
                    : .transcribing
                notify()
            } catch {
                captureStatus = "Recording could not start: \(error.localizedDescription)"
                speechStatus = "Live transcription unavailable"
                isRecording = false
                processPhase = .error
                notify()
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { recordingDuration += 1; notify() }
            }
        }
    }

    func cancelRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        Task { _ = await capture.stop() }
        recordingTitle = ""
        processPhase = .idle
        screen = .present
        notify()
    }

    func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        let duration = max(recordingDuration, 1)
        let files = captureFiles
        let title = recordingTitle
        captureFiles = nil
        captureStatus = "Finalizing the transcript on this Mac…"
        processPhase = .finalizingTranscription
        notify()

        Task {
            let transcript = await capture.stop()
            speechStatus = transcript.isEmpty ? "No speech detected" : "Transcript finalized locally"
            processPhase = .transcriptionComplete
            notify()

            captureStatus = "Creating the summary on this Mac…"
            processPhase = .summarizing
            notify()
            let notes: ProcessedMeetingNotes
            if transcript.isEmpty {
                notes = MeetingNotesProcessor.processFromTranscript(transcript)
            } else {
                do {
                    let cleaned = MeetingNotesProcessor.transcriptForSummarization(transcript)
                    let prompt = cleaned.isEmpty
                        ? transcript.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
                        : cleaned
                    let rawSummary = try await intelligence.summarize(transcript: String(prompt.prefix(40_000)))
                    notes = MeetingNotesProcessor.process(rawResponse: rawSummary, transcript: transcript)
                } catch {
                    notes = MeetingNotesProcessor.processFromTranscript(transcript)
                }
            }
            let draft = Meeting(
                id: 0,
                title: title,
                startedAt: Date().addingTimeInterval(-duration),
                duration: duration,
                participants: [],
                summary: notes.brief,
                decisions: notes.decisions,
                transcript: transcript,
                systemAudioPath: files?.systemAudioURL.path,
                microphonePath: files?.microphoneURL.path
            )
            do {
                let saved = try store?.insert(draft) ?? draft
                meetings.insert(saved, at: 0)
                selectedMeeting = saved
                storeStatus = "Recording saved locally"
                processPhase = .summaryComplete
            } catch {
                selectedMeeting = draft
                storeStatus = "Recording created but database save failed: \(error.localizedDescription)"
                processPhase = .error
            }
            screen = .summary
            recordingTitle = ""
            notify()
        }
    }

    func renameSelectedMeeting(to proposedTitle: String) throws {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, canRenameSelectedMeeting else { return }

        if selectedMeeting.id > 0 {
            try store?.updateTitle(forMeetingID: selectedMeeting.id, to: title)
        }
        selectedMeeting.title = title
        if let index = meetings.firstIndex(where: { $0.id == selectedMeeting.id }) {
            meetings[index].title = title
        }
        storeStatus = "Meeting name updated locally"
        notify()
    }

    @discardableResult
    func saveDaytonaOutcome(
        forMeetingID meetingID: Int64,
        decisionID: String?,
        action: String,
        previewURL: URL,
        artifactHTML: String
    ) throws -> DaytonaBuildOutcome {
        guard var meeting = meetings.first(where: { $0.id == meetingID }) ??
                (selectedMeeting.id == meetingID ? selectedMeeting : nil) else {
            throw MeetingStore.StoreError.statement("Pēsu could not find the meeting for this Daytona result.")
        }
        let outcome = try DaytonaBuildOutcome(
            decisionID: decisionID,
            action: action,
            previewURL: previewURL,
            artifactHTML: artifactHTML
        )
        let normalizedAction = outcome.action.lowercased()
        meeting.daytonaOutcomes.removeAll { existing in
            if let decisionID { return existing.decisionID == decisionID }
            return existing.decisionID == nil && existing.action.lowercased() == normalizedAction
        }
        meeting.daytonaOutcomes.append(outcome)
        meeting.daytonaOutcomes.sort { $0.completedAt < $1.completedAt }

        if meeting.id > 0 {
            try store?.updateDaytonaOutcomes(forMeetingID: meeting.id, outcomes: meeting.daytonaOutcomes)
        }
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        }
        if selectedMeeting.id == meeting.id {
            selectedMeeting = meeting
        }
        storeStatus = "Daytona outcome saved with this meeting"
        notify()
        return outcome
    }

    func deleteSelectedMeeting() throws {
        guard canDeleteSelectedMeeting else { return }
        let meeting = selectedMeeting
        try store?.deleteMeeting(withID: meeting.id)
        meetings.removeAll { $0.id == meeting.id }
        removeRecordingFile(at: meeting.systemAudioPath)
        removeRecordingFile(at: meeting.microphonePath)
        selectedMeeting = .empty
        storeStatus = "Meeting deleted from this Mac"
        screen = .present
        notify()
    }

    private func applyLiveTranscript(_ snapshot: LiveTranscriptSnapshot) {
        liveTranscriptSegments = snapshot.finalizedSegments
        liveTranscriptDraft = snapshot.volatileText
        speechStatus = snapshot.status
        let hasTranscript = !snapshot.finalizedSegments.isEmpty
            || !snapshot.volatileText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isRecording, hasTranscript {
            processPhase = .transcribing
        }
        notify()
    }

    private func normalizedMeeting(_ meeting: Meeting) -> Meeting {
        var normalized = meeting
        let processed = MeetingNotesProcessor.process(rawResponse: meeting.summary, transcript: meeting.transcript)
        normalized.summary = processed.brief
        if meeting.decisions.isEmpty {
            normalized.decisions = processed.decisions
        } else {
            let refined = MeetingNotesProcessor.refineStoredDecisions(meeting.decisions, transcript: meeting.transcript)
            normalized.decisions = refined.isEmpty ? processed.decisions : refined
        }
        return normalized
    }

    private func removeRecordingFile(at path: String?) {
        guard let path else { return }
        let recordingsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pēsu/Recordings", isDirectory: true)
            .standardizedFileURL.path
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        guard fileURL.path.hasPrefix(recordingsDirectory + "/") else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func refreshMicrophones() {
        let refreshed = AppleAudioCapture.availableMicrophones()
        microphones = refreshed.isEmpty
            ? [MicrophoneOption(id: MicrophoneOption.systemDefaultID, name: "System Default", detail: "Follows macOS input settings", captureDeviceID: nil)]
            : refreshed
        if !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = MicrophoneOption.systemDefaultID
            UserDefaults.standard.set(selectedMicrophoneID, forKey: microphoneSelectionKey)
        }
    }

    func refreshBuildCredentialStatus() {
        do {
            hasDaytonaAPIKey = try daytonaCredentials.containsAPIKey()
            daytonaCredentialAvailability = hasDaytonaAPIKey ? .configured : .missing
            daytonaCredentialStatus = hasDaytonaAPIKey
                ? "Stored securely in macOS Keychain"
                : "Not configured"
        } catch {
            hasDaytonaAPIKey = false
            daytonaCredentialAvailability = .unavailable
            daytonaCredentialStatus = "Keychain unavailable"
        }
        do {
            hasOpenAIAPIKey = try openAICredentials.containsAPIKey()
            openAICredentialAvailability = hasOpenAIAPIKey ? .configured : .missing
            openAICredentialStatus = hasOpenAIAPIKey
                ? "Stored securely in macOS Keychain"
                : "Not configured"
        } catch {
            hasOpenAIAPIKey = false
            openAICredentialAvailability = .unavailable
            openAICredentialStatus = "Keychain unavailable"
        }
        do {
            hasAzureOpenAIAPIKey = try azureOpenAICredentials.containsAPIKey()
            azureOpenAICredentialAvailability = hasAzureOpenAIAPIKey ? .configured : .missing
            azureOpenAICredentialStatus = hasAzureOpenAIAPIKey
                ? "Stored securely in macOS Keychain"
                : "Not configured"
        } catch {
            hasAzureOpenAIAPIKey = false
            azureOpenAICredentialAvailability = .unavailable
            azureOpenAICredentialStatus = "Keychain unavailable"
        }
    }

    private func refreshLocalModelStatus() {
        Task {
            let speech = await intelligence.speechStatus()
            let summary = await intelligence.modelStatus()
            speechModelStatus = Self.copy(for: speech, available: "Ready on device")
            summaryModelStatus = Self.copy(for: summary, available: "Ready on device")
            notify()
        }
    }

    private static func copy(for status: AppleServiceStatus, available: String) -> String {
        switch status {
        case .available: available
        case .unavailable(let reason): "Unavailable · \(reason)"
        }
    }

    private func loadCalendarMeetings() async {
        await loadCalendarSources()
        let today = Calendar.current.startOfDay(for: Date())
        let oneYearAgo = CalendarSyncWindow.pastStart(relativeTo: today)
        calendarMeetings = await calendar.fetchMeetings(
            from: oneYearAgo,
            to: futureSyncEnd,
            calendarIdentifiers: enabledCalendarIdentifiers
        )
        isCalendarSyncing = false
        updateCalendarCopy()
        notify()
    }

    private func loadCalendarSources() async {
        let sources = await calendar.calendarSources()
        calendarSources = CalendarFilterPolicy.options(from: sources, savedSelections: calendarSelections)
    }

    private func updateCalendarCopy() {
        switch calendar.connectionState {
        case .connected:
            calendarStatus = "Connected"
            if calendarSources.isEmpty {
                calendarDetail = "Apple Calendar is connected. No event calendars were found."
            } else if enabledCalendarCount == 0 {
                calendarDetail = "All calendars are disabled. Enable at least one calendar below."
            } else if calendarMeetings.isEmpty {
                calendarDetail = "No events were found in the \(enabledCalendarCount) enabled calendars."
            } else {
                calendarDetail = "\(calendarMeetings.count) events synced from \(enabledCalendarCount) of \(calendarSources.count) calendars."
            }
        case .notConnected:
            calendarStatus = "Not connected"
            calendarDetail = "Connect Apple Calendar to show your meetings in Pēsu."
        case .denied:
            calendarStatus = "Calendar access is off"
            calendarDetail = "Enable Pēsu in System Settings → Privacy & Security → Calendars."
        }
    }

    private func notify(_ change: AppModelChange = .content) { onChange?(change) }
}
