import Foundation

@main
enum BuildCredentialReadinessCheck {
    static func main() {
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            openAI: .configured
        ) == .ready)
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .missing,
            openAI: .configured
        ) == .missing(["Daytona"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .configured,
            openAI: .missing
        ) == .missing(["OpenAI"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .missing,
            openAI: .missing
        ) == .missing(["Daytona", "OpenAI"]))
        precondition(BuildCredentialReadiness.evaluate(
            daytona: .unavailable,
            openAI: .configured
        ) == .keychainUnavailable)
        print("Build credential readiness checks passed")
    }
}
