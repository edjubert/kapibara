import Foundation
import Darwin

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

/// What a poll of the port finds.
enum ServerProbe: Equatable {
    /// Nothing listens on the port.
    case down
    /// Something accepts TCP connections but /health does not answer
    /// "ok" yet: the server is loading a model.
    case starting
    /// /health answers "ok".
    case up
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

    /// Probes the port: down when nothing listens, starting when the
    /// TCP port is open but /health does not answer "ok" yet (the
    /// server is loading a model), up when /health answers "ok".
    static func probe(port: Int) -> ServerProbe {
        guard isPortOpen(port: port) else { return .down }
        return health(port: port) ? .up : .starting
    }

    /// True when a TCP connection to 127.0.0.1:port succeeds. Uses a
    /// raw socket so it works even when the server has not started
    /// its HTTP layer yet.
    private static func isPortOpen(port: Int) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
