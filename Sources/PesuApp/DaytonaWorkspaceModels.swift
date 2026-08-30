import Foundation

struct DaytonaDecisionContext: Codable, Equatable, Sendable {
    let id: String
    let text: String
    let evidence: String?
}

struct DaytonaWorkspaceContext: Codable, Equatable, Sendable {
    enum ValidationError: LocalizedError, Equatable {
        case missingBuildRequest

        var errorDescription: String? {
            switch self {
            case .missingBuildRequest:
                return "Choose a decision or describe what you want to build."
            }
        }
    }

    let meetingId: String
    let meetingTitle: String
    let brief: String
    let decisions: [DaytonaDecisionContext]
    let selectedAction: String?
    let userInstruction: String?

    static func make(
        meeting: Meeting,
        selectedAction: String,
        userInstruction: String
    ) throws -> DaytonaWorkspaceContext {
        let action = clean(selectedAction, limit: 1_000)
        let instruction = clean(userInstruction, limit: 2_000)
        guard !action.isEmpty || !instruction.isEmpty else {
            throw ValidationError.missingBuildRequest
        }

        var transcriptByID: [String: String] = [:]
        for segment in meeting.transcript where transcriptByID[segment.id] == nil {
            transcriptByID[segment.id] = segment.text
        }
        let decisions = meeting.decisions.prefix(8).map { decision in
            let evidence = transcriptByID[decision.evidenceSegmentID].map {
                clean($0, limit: 500)
            }.flatMap { $0.isEmpty ? nil : $0 }
            return DaytonaDecisionContext(
                id: clean(decision.id, limit: 40),
                text: clean(decision.text, limit: 500),
                evidence: evidence
            )
        }.filter { !$0.text.isEmpty }

        return DaytonaWorkspaceContext(
            meetingId: String(meeting.id),
            meetingTitle: clean(meeting.title, limit: 200),
            brief: clean(meeting.summary, limit: 2_000),
            decisions: decisions,
            selectedAction: action.isEmpty ? nil : action,
            userInstruction: instruction.isEmpty ? nil : instruction
        )
    }

    private static func clean(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(limit))
    }
}

struct DaytonaWorkspaceEvent: Decodable, Equatable, Sendable {
    enum EventType: String, Decodable, Sendable {
        case preparing
        case creatingSandbox = "creating_sandbox"
        case installingAgent = "installing_agent"
        case runningAgent = "running_agent"
        case activity
        case startingPreview = "starting_preview"
        case creatingPreview = "creating_preview"
        case ready
        case failed

        var appProcessPhase: AppProcessPhase {
            switch self {
            case .preparing, .creatingSandbox, .installingAgent:
                .daytonaStarting
            case .runningAgent, .activity, .startingPreview, .creatingPreview:
                .daytonaWorking
            case .ready:
                .daytonaComplete
            case .failed:
                .error
            }
        }
    }

    let type: EventType
    let message: String
    let sandboxId: String?
    let previewURL: URL?
    let artifactHTML: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case sandboxId
        case previewURL = "previewUrl"
        case artifactHTML = "artifactHtml"
    }

    static func decode(line: String) throws -> DaytonaWorkspaceEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !data.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Workspace event was empty.")
            )
        }
        let event = try JSONDecoder().decode(DaytonaWorkspaceEvent.self, from: data)
        if event.type == .ready {
            guard let url = event.previewURL,
                  url.scheme?.lowercased() == "https" else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Ready event did not contain a safe preview URL.")
                )
            }
            guard let artifactHTML = event.artifactHTML,
                  artifactHTML.lengthOfBytes(using: .utf8) >= 500,
                  artifactHTML.lengthOfBytes(using: .utf8) <= 500_000 else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Ready event did not contain a bounded HTML artifact.")
                )
            }
        }
        return event
    }
}
