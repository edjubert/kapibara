import Foundation
import Combine
import AppKit
import Darwin

/// Server lifecycle state, as seen by the menu bar.
enum ServerState: Equatable {
    /// No answer on the port.
    case down
    /// A server answers /health but /v1/models is not ready yet (loading).
    case starting
    /// A server is up and serving a model.
    case up(model: ServedModel)
}

struct LogEditor: Identifiable {
    let bundleIdentifier: String
    let name: String
    let applicationURL: URL

    var id: String { bundleIdentifier }
}

/// Polls kapitsa and the local server, publishes what the menu shows.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private static let logEditorPreferenceKey = "logEditorBundleIdentifier"
    static let systemDefaultLogEditorID = "system-default"

    @Published private(set) var state: ServerState = .down
    /// Increments on every state change, so the menu bar label (which
    /// lives outside the normal SwiftUI refresh cycle) can be forced to
    /// rebuild with `.id(model.stateVersion)`.
    @Published private(set) var stateVersion: Int = 0
    /// What the engine is doing right now (prefill / generating),
    /// inferred from the serve log tail.
    @Published private(set) var engineActivity: EngineActivity = .idle
    @Published private(set) var installedModels: [InstalledModel] = []
    @Published private(set) var catalog: [CatalogVariant] = []
    @Published private(set) var modelsLoading = false
    @Published private(set) var catalogLoading = false
    /// Full doctor model entries, kept to look up each installed
    /// model's context limit by matching `dir`.
    @Published private(set) var doctorModels: [DoctorModel] = []
    @Published private(set) var activity: [ActivityEntry] = []
    /// Increments on every refreshServer, so the Activity section can
    /// be forced to rebuild with `.id(model.activityVersion)` even when
    /// the parsed entries are identical (SwiftUI skips equal arrays).
    @Published private(set) var activityVersion: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

    /// The model currently downloading, nil when idle.
    @Published private(set) var downloadingModel: String?
    @Published private(set) var downloadError: String?

    /// Last lines of `~/.kapibara/kapibara.log`, for the Logs section.
    @Published private(set) var logLines: [String] = []
    @Published private(set) var logEditors: [LogEditor] = []
    @Published private(set) var selectedLogEditorID = "system-default"

    /// Port the app manages. Stored so the settings UI can change it.
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "port") }
    }

    /// Context window in tokens for `kapitsa serve --context`. 0 means
    /// "let kapitsa decide" (its default, memory-dependent). Stored so
    /// the slider keeps its position across launches.
    @Published var contextTokens: Int {
        didSet { UserDefaults.standard.set(contextTokens, forKey: "contextTokens") }
    }

    private let serverProcess = ServerProcess()
    private let downloader = DownloadProcess()
    private let modelsStore = ModelsStore()
    private var modelSubscriptions = Set<AnyCancellable>()

    /// True when the app itself spawned the running server, so the
    /// Stop button only ever kills a process it owns.
    @Published private(set) var ownsServer: Bool = false

    var pollInterval: TimeInterval = 2

    /// Max time in `.starting` without /health answering "ok" before
    /// giving up and going back to `.down`.
    static let startupTimeout: TimeInterval = 120

    /// When the server entered `.starting`, for the startup timeout.
    private var startingSince: Date?

    private var timer: DispatchSourceTimer?

    /// Watches the kapitsa log directory: fires on every write, so the
    /// Activity section streams new requests in real time instead of
    /// waiting for the next poll.
    private var logWatcher: DispatchSourceFileSystemObject?

    private init() {
        port = UserDefaults.standard.object(forKey: "port") as? Int ?? 8000
        contextTokens = UserDefaults.standard.object(forKey: "contextTokens") as? Int ?? 0
        logEditors = Self.detectLogEditors()
        let preferredLogEditorID = UserDefaults.standard.string(forKey: Self.logEditorPreferenceKey)
            ?? Self.systemDefaultLogEditorID
        if preferredLogEditorID == Self.systemDefaultLogEditorID
            || logEditors.contains(where: { $0.bundleIdentifier == preferredLogEditorID }) {
            selectedLogEditorID = preferredLogEditorID
        } else {
            selectedLogEditorID = Self.systemDefaultLogEditorID
            UserDefaults.standard.set(Self.systemDefaultLogEditorID, forKey: Self.logEditorPreferenceKey)
        }
        AppLog.info("Kapibara started, port \(port)")
        // Combine immediately delivers the cached snapshot, before the
        // first asynchronous refresh has a chance to run.
        modelsStore.$snapshot
            .sink { [weak self] snapshot in
                self?.installedModels = snapshot.installedModels
                self?.catalog = snapshot.catalogVariants
                self?.doctorModels = snapshot.doctorModels
                self?.lastRefresh = snapshot.lastRefresh
            }
            .store(in: &modelSubscriptions)
        modelsStore.$isRefreshingInstalled.assign(to: &$modelsLoading)
        modelsStore.$isRefreshingCatalog.assign(to: &$catalogLoading)
        modelsStore.$refreshError
            .sink { [weak self] error in
                self?.lastError = error.map(Self.describe)
            }
            .store(in: &modelSubscriptions)
        NotificationCenter.default.addObserver(
            forName: .downloadFinished,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let code = note.userInfo?["exitCode"] as? Int32 ?? -1
            self?.downloadError = code == 0 ? nil : L10n.t("download.error")
            if code == 0 {
                AppLog.info("Download finished successfully")
            } else {
                AppLog.error("Download failed with exit code \(code)")
            }
            self?.refreshModels()
            self?.refreshLogs()
        }
        refresh()
        refreshLogs()
        // DispatchSourceTimer on a global queue: a Timer.publish on the
        // main run loop does not fire reliably in a menu bar agent app
        // (no active window, app nap, ...).
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.refreshServer() }
        t.resume()
        timer = t
        startLogWatcher()
    }

    /// Starts watching the kapitsa log directory. Any write to a file
    /// in that directory triggers `refreshActivity()`, which re-reads
    /// the serve log and updates the Activity section in real time.
    private func startLogWatcher() {
        let dir = ActivityLog.logDirectory().path
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            // Debounce: multiple writes can fire in quick succession.
            self?.refreshActivity()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        logWatcher = source
    }

    /// Re-reads the serve log and updates activity + engine state,
    /// without touching the server state. Called by the log watcher
    /// on every write to the log directory.
    private func refreshActivity() {
        let port = self.port
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let activity = ActivityLog.entries(port: port)
            let engine = ActivityLog.currentActivity(port: port)
            DispatchQueue.main.async {
                guard let self else { return }
                self.activity = activity
                self.activityVersion += 1
                self.engineActivity = engine
            }
        }
    }

    /// Starts downloading a catalog model. No-op when a download is
    /// already running.
    func startDownload(_ model: String) {
        guard !downloader.isRunning else { return }
        AppLog.info("Starting download: \(model)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.downloader.start(model: model)
                DispatchQueue.main.async {
                    self?.downloadingModel = model
                    self?.downloadError = nil
                }
            } catch {
                AppLog.error("Download start failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.downloadError = Self.describe(error)
                }
            }
        }
    }

    /// Cancels the running download. Kapitsa keeps the parts already
    /// fetched and resumes on the next pull.
    func cancelDownload() {
        AppLog.warn("Download cancelled by user")
        downloader.cancel()
    }

    /// Spawns `kapitsa serve` on the configured port, pinned to `model`
    /// when given, with the configured context when set. The next poll
    /// picks the server up.
    func startServer(model: String?) {
        let port = self.port
        let ctx = self.contextTokens > 0 ? self.contextTokens : nil
        AppLog.info("Starting server on port \(port), model: \(model ?? "default"), context: \(ctx.map(String.init) ?? "default")")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.serverProcess.start(port: port, model: model, context: ctx)
                DispatchQueue.main.async {
                    self?.ownsServer = true
                    self?.lastError = nil
                    // Optimistic transition: the user just clicked, the
                    // server is starting de facto. Do NOT call
                    // refreshServer() here: the port is not open yet and
                    // the probe would flip the state back to .down. The
                    // next poll (within 2s) will detect the open port.
                    if self?.state != .starting {
                        self?.state = .starting
                        self?.stateVersion += 1
                    }
                }
            } catch {
                AppLog.error("Server start failed: \(error.localizedDescription)")
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
        AppLog.info("Stopping server")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serverProcess.stop()
            DispatchQueue.main.async {
                self?.ownsServer = false
                self?.refreshServer()
            }
        }
    }

    /// Full refresh: server state plus the model catalog. Used at
    /// startup and by the manual Refresh button.
    func refresh() {
        refreshServer()
        refreshModels()
    }

    /// Light refresh: server health and activity log only. Called by
    /// the poll timer — must stay fast, so it never runs `kapitsa
    /// doctor` (a multi-second hardware analysis).
    func refreshServer() {
        let port = self.port
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let probe = ServerClient.probe(port: port)
            let served = probe == .up ? ServerClient.servedModel(port: port) : nil
            let activity = ActivityLog.entries(port: port)
            let engine = ActivityLog.currentActivity(port: port)
            DispatchQueue.main.async {
                guard let self else { return }
                let newState: ServerState
                switch (probe, served) {
                case (.up, let model?):
                    newState = .up(model: model)
                case (.up, nil):
                    newState = .starting
                case (.starting, _):
                    // Port open but /health not "ok" yet. Give up after
                    // the startup timeout: the server is stuck loading.
                    if let since = self.startingSince,
                       Date().timeIntervalSince(since) > Self.startupTimeout {
                        newState = .down
                        AppLog.warn("Server startup timed out after \(Int(Self.startupTimeout))s")
                    } else {
                        newState = .starting
                    }
                case (.down, _):
                    newState = .down
                }
                if newState != self.state {
                    self.state = newState
                    self.stateVersion += 1
                    AppLog.info("Server state: \(newState)")
                }
                // Track when we entered .starting, reset otherwise.
                if case .starting = newState {
                    if self.startingSince == nil {
                        self.startingSince = Date()
                    }
                } else {
                    self.startingSince = nil
                }
                if case .down = newState {
                    // Our child died or was killed: we no longer own a server.
                    if self.ownsServer && !self.serverProcess.isRunning {
                        self.ownsServer = false
                    }
                }
                self.activity = activity
                self.activityVersion += 1
                self.engineActivity = engine
            }
        }
    }

    /// Refreshes installed models and the catalog independently, keeping
    /// the cached inventory visible while the CLI runs.
    /// Called at startup, after a download finishes, and on manual
    /// refresh.
    func refreshModels() {
        guard KapitsaCLI.isInstalled else {
            AppLog.error("kapitsa not found")
            lastError = L10n.t("error.not_installed")
            return
        }
        downloadingModel = downloader.isRunning ? downloader.currentModel : nil
        modelsStore.refresh()
    }

    /// Reloads the last lines of the app log for the Logs section.
    func refreshLogs() {
        logLines = AppLog.recentLines(50)
    }

    /// Opens the server activity log with the most recently selected app.
    func openActivityLog() {
        openActivityLog(using: selectedLogEditorID)
    }

    /// Opens the server activity log with the selected app and remembers
    /// that choice for the next click on the main button.
    func openActivityLog(using bundleIdentifier: String) {
        let url = ActivityLog.logFileURL(port: port)
        UserDefaults.standard.set(bundleIdentifier, forKey: Self.logEditorPreferenceKey)
        selectedLogEditorID = bundleIdentifier

        guard bundleIdentifier != Self.systemDefaultLogEditorID else {
            if !NSWorkspace.shared.open(url) {
                AppLog.error("Failed to open activity log with the system default app")
            }
            return
        }

        guard let editor = logEditors.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            AppLog.error("Selected log editor is no longer installed: \(bundleIdentifier)")
            UserDefaults.standard.set(Self.systemDefaultLogEditorID, forKey: Self.logEditorPreferenceKey)
            selectedLogEditorID = Self.systemDefaultLogEditorID
            if !NSWorkspace.shared.open(url) {
                AppLog.error("Failed to open activity log with the system default app")
            }
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: editor.applicationURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: { _, error in
                if let error {
                    AppLog.error("Failed to open activity log in \(editor.name): \(error.localizedDescription)")
                }
            }
        )
    }

    private static func detectLogEditors() -> [LogEditor] {
        let knownEditors = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.vscodium",
            "dev.zed.Zed",
            "se.ziran.Gram",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.sublimetext.4",
            "com.sublimetext.3",
            "com.macromates.TextMate",
            "com.barebones.bbedit",
            "com.coteditor.CotEditor",
            "com.panic.Nova",
        ]

        let known = knownEditors.compactMap { bundleIdentifier -> LogEditor? in
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                return nil
            }

            let bundle = Bundle(url: applicationURL)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? applicationURL.deletingPathExtension().lastPathComponent

            return LogEditor(
                bundleIdentifier: bundleIdentifier,
                name: name,
                applicationURL: applicationURL
            )
        }

        let textFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kapibara-activity-log.txt")
        let registeredEditors = NSWorkspace.shared.urlsForApplications(toOpen: textFile)
            .compactMap { applicationURL -> LogEditor? in
                guard let bundle = Bundle(url: applicationURL),
                      let bundleIdentifier = bundle.bundleIdentifier
                else {
                    return nil
                }

                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? applicationURL.deletingPathExtension().lastPathComponent

                return LogEditor(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    applicationURL: applicationURL
                )
            }

        var editorsByBundleIdentifier: [String: LogEditor] = [:]
        for editor in known + registeredEditors {
            editorsByBundleIdentifier[editor.bundleIdentifier] = editor
        }
        return editorsByBundleIdentifier.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

    /// The doctor entry for an installed model, matched by directory.
    /// The `dir` from `kapitsa list --json` is the same path as the
    /// `dir` in `kapitsa doctor --json`'s models array.
    func doctorEntry(for modelName: String) -> DoctorModel? {
        guard let installed = installedModels.first(where: { $0.name == modelName }) else {
            return nil
        }
        return doctorModels.first { $0.dir == installed.dir }
    }

    /// The model's hard context limit (its trained max), from doctor.
    func contextLimit(for modelName: String) -> Int? {
        doctorEntry(for: modelName)?.contextLimit
    }

    /// The context kapitsa would pick by default for this model on
    /// this Mac (memory-dependent), from doctor.
    func defaultContext(for modelName: String) -> Int? {
        doctorEntry(for: modelName)?.defaultContext
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

    /// Aggregate stats over the parsed activity.
    var activitySummary: ActivitySummary {
        ActivitySummary.compute(activity)
    }

    /// The most recent activity entries, newest last, capped for the UI.
    var recentActivity: [ActivityEntry] {
        Array(activity.suffix(5))
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
