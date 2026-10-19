import Foundation

/// A mutable box that is safe to capture in a `@Sendable` closure.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

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
/// All methods are synchronous: the menu must never hang on a stuck
/// server, and the short timeout bounds the wait.
enum ServerClient {
    /// Short timeouts: a poll must never block the UI for long.
    private static let timeout: TimeInterval = 2

    private static func getSync(_ path: String, port: Int) -> Data? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let box = LockedBox<Data?>(nil)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                box.value = data
            }
            sem.signal()
        }.resume()
        // Bound the wait by the timeout plus a margin, so a hung
        // connection cannot block the caller forever.
        _ = sem.wait(timeout: .now() + timeout + 1)
        return box.value
    }

    /// `GET /health`: is a server up on this port?
    static func health(port: Int) -> Bool {
        guard let data = getSync("/health", port: port),
              let status = try? JSONDecoder().decode([String: String].self, from: data)["status"]
        else { return false }
        return status == "ok"
    }

    /// `GET /v1/models`: the model being served, nil when no server answers.
    static func servedModel(port: Int) -> ServedModel? {
        guard let data = getSync("/v1/models", port: port),
              let response = try? JSONDecoder().decode(ModelsResponse.self, from: data)
        else { return nil }
        return response.data.first
    }
}
