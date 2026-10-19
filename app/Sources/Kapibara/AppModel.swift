import Foundation
import Combine
import AppKit

/// Server lifecycle state, as seen by the menu bar.
enum ServerState: Equatable {
    /// No answer on the port.
    case down
    /// A server answers /health but /v1/models is not ready yet (loading).
    case starting
    /// A server is up and serving a model.
    case up(model: ServedModel)
}

/// Polls kapitsa and the local server, publishes what the menu shows.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var state: ServerState = .down
    @Published private(set) var installedModels: [InstalledModel] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

    /// Port the app manages. Stored so the settings UI can change it.
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }

    private var timer: AnyCancellable?

    var pollInterval: TimeInterval = 5

    private init() {
        port = UserDefaults.standard.object(forKey: "port") as? Int ?? 8000
        refresh()
        timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// One refresh cycle: server state on the port, then the model list.
    /// Both run on background queues; the UI updates on the main thread.
    func refresh() {
        let port = self.port
        Task { [weak self] in
            let up = await ServerClient.health(port: port)
            let served = up ? await ServerClient.servedModel(port: port) : nil
            await MainActor.run {
                guard let self else { return }
                switch (up, served) {
                case (true, let model?):
                    self.state = .up(model: model)
                case (true, nil):
                    self.state = .starting
                case (false, _):
                    self.state = .down
                }
            }
        }
        Task { [weak self] in
            guard KapitsaCLI.isInstalled else {
                await MainActor.run {
                    self?.lastError = L10n.t("error.not_installed")
                }
                return
            }
            do {
                let models = try await Task.detached {
                    try KapitsaCLI.list()
                }.value
                await MainActor.run {
                    self?.installedModels = models
                    self?.lastError = nil
                    self?.lastRefresh = Date()
                }
            } catch {
                await MainActor.run {
                    self?.lastError = Self.describe(error)
                }
            }
        }
    }

    /// Short label in the menu bar: the served model, or the state.
    var barTitle: String {
        switch state {
        case .up(let model): return model.id
        case .starting: return L10n.t("bar.starting")
        case .down: return L10n.t("bar.off")
        }
    }

    /// Green dot when a server is up, grey otherwise.
    var isUp: Bool {
        if case .up = state { return true }
        return false
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case KapitsaError.processFailed(let code):
            return L10n.t("error.exited", code)
        case KapitsaError.badJSON:
            return L10n.t("error.bad_json")
        default:
            return error.localizedDescription
        }
    }
}
