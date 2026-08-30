import Foundation

@main
enum DaytonaWorkspaceContextCheck {
    static func main() throws {
        let meeting = Meeting(
            id: 42,
            title: "Private launch review",
            startedAt: Date(timeIntervalSince1970: 1_787_840_000),
            duration: 1_800,
            participants: ["Maya", "Alex"],
            summary: "The team agreed to prototype a launch status page.",
            decisions: [
                Decision(id: "01", text: "Build a launch status page.", evidenceSegmentID: "segment-2")
            ],
            transcript: [
                TranscriptSegment(id: "segment-1", timestamp: "00:05", speaker: "Maya", text: "This sentence must stay private."),
                TranscriptSegment(id: "segment-2", timestamp: "00:15", speaker: "Alex", text: "Build a launch status page with three milestones.")
            ],
            systemAudioPath: "/private/audio/system.wav",
            microphonePath: "/private/audio/microphone.wav"
        )

        let context = try DaytonaWorkspaceContext.make(
            meeting: meeting,
            selectedAction: meeting.decisions[0].text,
            userInstruction: "Make it warm and easy to scan."
        )
        let data = try JSONEncoder().encode(context)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        precondition(Set(json.keys) == ["meetingId", "meetingTitle", "brief", "decisions", "selectedAction", "userInstruction"])
        precondition(json["meetingId"] as? String == "42")
        precondition(json["selectedAction"] as? String == "Build a launch status page.")
        precondition(json["userInstruction"] as? String == "Make it warm and easy to scan.")

        let decisions = json["decisions"] as! [[String: Any]]
        precondition(decisions.count == 1)
        precondition(decisions[0]["evidence"] as? String == "Build a launch status page with three milestones.")

        let encoded = String(decoding: data, as: UTF8.self)
        precondition(!encoded.contains("This sentence must stay private."))
        precondition(!encoded.contains("system.wav"))
        precondition(!encoded.contains("microphone.wav"))
        precondition(!encoded.contains("transcript"))
        precondition(!encoded.contains("participants"))

        var duplicateIDMeeting = meeting
        duplicateIDMeeting.transcript.append(
            TranscriptSegment(id: "segment-2", timestamp: "00:25", speaker: "Maya", text: "A duplicate must not crash or override evidence.")
        )
        let duplicateSafeContext = try DaytonaWorkspaceContext.make(
            meeting: duplicateIDMeeting,
            selectedAction: meeting.decisions[0].text,
            userInstruction: ""
        )
        precondition(duplicateSafeContext.decisions[0].evidence == "Build a launch status page with three milestones.")

        do {
            _ = try DaytonaWorkspaceContext.make(meeting: meeting, selectedAction: "  ", userInstruction: "\n")
            preconditionFailure("An empty build request must be rejected")
        } catch DaytonaWorkspaceContext.ValidationError.missingBuildRequest {
            // Expected.
        }

        let artifactHTML = "<!doctype html><html><body>" + String(repeating: "Outcome", count: 90) + "</body></html>"
        let readyData = try JSONSerialization.data(withJSONObject: [
            "type": "ready",
            "message": "Preview is ready",
            "previewUrl": "https://example.daytona.app",
            "artifactHtml": artifactHTML
        ])
        let ready = try DaytonaWorkspaceEvent.decode(line: String(decoding: readyData, as: UTF8.self))
        precondition(ready.type == .ready)
        precondition(ready.previewURL?.absoluteString == "https://example.daytona.app")
        precondition(ready.artifactHTML == artifactHTML)

        let activity = try DaytonaWorkspaceEvent.decode(line: """
        {"type":"activity","message":"Created index.html"}
        """)
        precondition(activity.type == .activity)
        precondition(activity.message == "Created index.html")

        do {
            _ = try DaytonaWorkspaceEvent.decode(line: """
            {"type":"ready","message":"Preview is ready","previewUrl":"file:///private/tmp/index.html"}
            """)
            preconditionFailure("Unsafe preview schemes must be rejected")
        } catch {
            // Expected.
        }

        print("Daytona workspace privacy context and event decoding checks passed")
    }
}
