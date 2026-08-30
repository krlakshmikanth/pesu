import Foundation

@main
enum AzureOpenAIConnectionCheck {
    static func main() throws {
        let configuration = try AzureOpenAIConfiguration(
            endpoint: "https://resource.openai.azure.com",
            deployment: "landing-page-model"
        )
        let request = try AzureOpenAIConnectionChecker.makeRequest(
            configuration: configuration,
            apiKey: "private-test-key"
        )

        precondition(request.url?.absoluteString == "https://resource.openai.azure.com/openai/v1/responses")
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "api-key") == "private-test-key")
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        precondition(request.timeoutInterval == 20)

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["model"] as? String == "landing-page-model")
        precondition(body["input"] as? String == "Reply with OK.")
        precondition(body["store"] as? Bool == false)
        precondition(body["max_output_tokens"] as? Int == 16)
        precondition(!String(data: request.httpBody!, encoding: .utf8)!.contains("private-test-key"))

        let expected: [(Int, AzureOpenAIConnectionResult)] = [
            (200, .working),
            (204, .working),
            (400, .responsesUnsupported),
            (401, .invalidAPIKey),
            (403, .accessDenied),
            (404, .endpointOrDeploymentNotFound),
            (429, .rateOrCapacityLimited),
            (500, .serviceUnavailable),
            (503, .serviceUnavailable),
            (302, .unexpectedResponse)
        ]
        for (status, result) in expected {
            precondition(AzureOpenAIConnectionChecker.classify(statusCode: status) == result)
            precondition(!result.message.contains("private-test-key"))
        }
        precondition(AzureOpenAIConnectionResult.working.isWorking)
        precondition(!AzureOpenAIConnectionResult.invalidAPIKey.isWorking)
        print("Azure OpenAI connection request and response checks passed")
    }
}
