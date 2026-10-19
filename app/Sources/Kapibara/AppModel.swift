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
    @Published private(set) var catalog: [CatalogVariant] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

    /// The model currently downloading, nil when idle.
    @Published private(set) var downloadingModel: String?
    @Published private(set) var downloadError: String?

    /// Port the app manages. Stored so the settings UI can change it.
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }

    private var timer: AnyCancellable?
    private let serverProcess = ServerProcess()
    private let downloader = DownloadProcess()

    /// True when the app itself spawned the running server, so the
    /// Stop button only ever kills a process it owns.
    @Published private(set) var ownsServer: Bool = false

    var pollInterval: TimeInterval = 5

    private init() {
        port = UserDefaults.standard.object(forKey: "port") as? Int ?? 8000
        NotificationCenter.default.addObserver(
            forName: .downloadFinished,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let code = note.userInfo?["exitCode"] as? Int32 ?? -1
            self?.downloadError = code == 0 ? nil : L10n.t("download.error")
            self?.refresh()
        }
        refresh()
        timer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Starts downloading a catalog model. No-op when a download is
    /// already running.
    func startDownload(_ model: String) {
        guard !downloader.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.downloader.start(model: model)
                DispatchQueue.main.async {
                    self?.downloadingModel = model
                    self?.downloadError = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self?.downloadError = Self.describe(error)
                }
            }
        }
    }

    /// Cancels the running download. Kapitsa keeps the parts already
    /// fetched and resumes on the next pull.
    func cancelDownload() {
        downloader.cancel()
    }

    /// Spawns `kapitsa serve` on the configured port, pinned to `model`
    /// when given. The next poll picks the server up.
    func startServer(model: String?) {
        let port = self.port
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.serverProcess.start(port: port, model: model)
                DispatchQueue.main.async {
                    self?.ownsServer = true
                    self?.lastError = nil
                    self?.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = Self.describe(error)
                }
            }
        }
    }

    /// Stops the server, but only when the app started it. A server
    /// launched outside the app (brew services, a terminal) is left
    /// alone.
    func stopServer() {
        guard ownsServer else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serverProcess.stop()
            DispatchQueue.main.async {
                self?.ownsServer = false
                self?.refresh()
            }
        }
    }

    /// One refresh cycle: server state on the port, then the model list.
    /// Both run on background queues; the UI updates on the main thread.
    func refresh() {
        let port = self.port
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let up = ServerClient.health(port: port)
            let served = up ? ServerClient.servedModel(port: port) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                switch (up, served) {
                case (true, let model?):
                    self.state = .up(model: model)
                case (true, nil):
                    self.state = .starting
                case (false, _):
                    self.state = .down
                    // Our child died or was killed: we no longer own a server.
                    if self.ownsServer && !self.serverProcess.isRunning {
                        self.ownsServer = false
                    }
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard KapitsaCLI.isInstalled else {
                DispatchQueue.main.async {
                    self?.lastError = L10n.t("error.not_installed")
                }
                return
            }
            do {
                let models = try KapitsaCLI.list()
                let doctor = try KapitsaCLI.doctor()
                DispatchQueue.main.async {
                    self?.installedModels = models
                    self?.catalog = doctor.catalogVariants
                    self?.downloadingModel = (self?.downloader.isRunning == true)
                        ? self?.downloader.currentModel : nil
                    self?.lastError = nil
                    self?.lastRefresh = Date()
                }
            } catch {
                DispatchQueue.main.async {
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

    /// The `<model>:<variant>` names already on disk, for marking the
    /// catalog entries as downloaded.
    var installedModelIds: Set<String> {
        Set(installedModels.map(\.name))
    }

    /// Catalog model names, in catalog order, without duplicates.
    var catalogModels: [String] {
        var seen: Set<String> = []
        return catalog.filter { seen.insert($0.model).inserted }.map(\.model)
    }

    /// The variants of one catalog model, in catalog order.
    func variants(for model: String) -> [CatalogVariant] {
        catalog.filter { $0.model == model }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case KapitsaError.processFailed(let code):
            return L10n.t("error.exited", code)
        case KapitsaError.badJSON:
            return L10n.t("error.bad_json")
        case KapitsaError.noBinary:
            return L10n.t("error.not_installed")
        default:
            return error.localizedDescription
        }
    }
}
