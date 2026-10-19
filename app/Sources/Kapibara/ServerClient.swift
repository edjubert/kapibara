import Foundation

/// The model being served, from `GET /v1/models`.
struct ServedModel: Codable, Equatable {
    let id: String
    let displayName: String?
    let contextLength: Int?
    let contextFit: Int?
    let slots: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case contextLength = "context_length"
        case contextFit = "context_fit"
        case slots
    }
}

struct ModelsResponse: Codable, Equatable {
    let data: [ServedModel]
}

/// HTTP client for the local Kapitsa server (http://127.0.0.1:PORT).
enum ServerClient {
    /// Short timeouts: the menu must never hang on a stuck server.
    private static let timeout: TimeInterval = 2

    private static func get(_ path: String, port: Int) async throws -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// `GET /health`: is a server up on this port?
    static func health(port: Int) async -> Bool {
        guard let data = try? await get("/health", port: port) else { return false }
        return (try? JSONDecoder().decode([String: String].self, from: data))?["status"] == "ok"
    }

    /// `GET /v1/models`: the model being served, nil when no server answers.
    static func servedModel(port: Int) async -> ServedModel? {
        guard let data = try? await get("/v1/models", port: port) else { return nil }
        return try? JSONDecoder().decode(ModelsResponse.self, from: data).data.first
    }
}
