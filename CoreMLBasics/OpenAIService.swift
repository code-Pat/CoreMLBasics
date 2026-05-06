// OpenAIService.swift
// Phase 1에서 가져온 OpenAI 연동 — CoreMLBasics에서는 askStructured만 사용

import Foundation

class OpenAIService {
    private let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    struct ChatResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: Message
            struct Message: Codable { let content: String }
        }
    }

    private func buildRequest(body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // Document scan 결과를 JSON으로 파싱할 때 사용
    func askStructured(_ userMessage: String, systemPrompt: String = "주어진 텍스트를 요청한 JSON 형식으로 변환하세요.") async throws -> String {
        let request = try buildRequest(body: [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "response_format": ["type": "json_object"]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            // 실제 OpenAI 에러 메시지를 에러로 던짐
            let body = String(data: data, encoding: .utf8) ?? "응답 없음"
            print("❌ OpenAI 에러 [\(http.statusCode)]: \(body)")
            throw NSError(domain: "OpenAIError",
                          code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "OpenAI [\(http.statusCode)]: \(body)"])
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
}
