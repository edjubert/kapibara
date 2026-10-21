import Foundation
import Combine

/// The last successful inventory, displayed before launching any CLI work.
struct ModelsSnapshot: Codable, Equatable {
    var version = 1
    var installedModels: [InstalledModel] = []
    var catalogVariants: [CatalogVariant] = []
    var doctorModels: [DoctorModel] = []
    var installedUpdatedAt: Date?
    var catalogUpdatedAt: Date?

    var lastRefresh: Date? {
        [installedUpdatedAt, catalogUpdatedAt].compactMap { $0 }.max()
    }
}

/// Readable JSON, replaced atomically so an interrupted write keeps the
/// previous inventory intact.
struct ModelsCache {
    let url: URL

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".kapibara/models.json")) {
        self.url = url
    }

    func load() throws -> ModelsSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(ModelsSnapshot.self, from: data)
        guard snapshot.version == 1 else {
            throw CacheError.unsupportedVersion(snapshot.version)
        }
        return snapshot
    }

    func save(_ snapshot: ModelsSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    enum CacheError: Error {
        case unsupportedVersion(Int)
    }
}

/// Refreshes the quick installed-model list and the slower doctor report
/// independently. Publications and refresh requests run on the main queue.
final class ModelsStore: ObservableObject {
    @Published private(set) var snapshot: ModelsSnapshot
    @Published private(set) var isRefreshingInstalled = false
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var refreshError: Error?

    private let cache: ModelsCache
    private let listModels: () throws -> [InstalledModel]
    private let doctorReport: () throws -> DoctorReport
    private let cacheQueue = DispatchQueue(label: "com.edjubert.Kapibara.models-cache", qos: .utility)
    private var refreshPending = false

    init(
        cache: ModelsCache = ModelsCache(),
        listModels: @escaping () throws -> [InstalledModel] = KapitsaCLI.list,
        doctorReport: @escaping () throws -> DoctorReport = KapitsaCLI.doctor
    ) {
        self.cache = cache
        self.listModels = listModels
        self.doctorReport = doctorReport
        do {
            snapshot = try cache.load() ?? ModelsSnapshot()
        } catch {
            snapshot = ModelsSnapshot()
            AppLog.warn("Ignoring model cache: \(error.localizedDescription)")
        }
    }

    func refresh() {
        guard !isRefreshingInstalled && !isRefreshingCatalog else {
            // A download may have finished during this refresh. Run one
            // more pass afterwards rather than starting competing probes.
            refreshPending = true
            return
        }
        refreshError = nil
        isRefreshingInstalled = true
        isRefreshingCatalog = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.listModels() }
            DispatchQueue.main.async {
                switch result {
                case .success(let models):
                    self.updateSnapshot {
                        $0.installedModels = models
                        $0.installedUpdatedAt = Date()
                    }
                case .failure(let error):
                    self.refreshError = error
                    AppLog.error("Installed model refresh failed: \(error.localizedDescription)")
                }
                self.isRefreshingInstalled = false
                self.finishRefresh()
            }
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.doctorReport() }
            DispatchQueue.main.async {
                switch result {
                case .success(let report):
                    self.updateSnapshot {
                        $0.catalogVariants = report.catalogVariants
                        $0.doctorModels = report.models
                        $0.catalogUpdatedAt = Date()
                    }
                case .failure(let error):
                    self.refreshError = error
                    AppLog.error("Catalog refresh failed: \(error.localizedDescription)")
                }
                self.isRefreshingCatalog = false
                self.finishRefresh()
            }
        }
    }

    private func updateSnapshot(_ update: (inout ModelsSnapshot) -> Void) {
        var updated = snapshot
        update(&updated)
        snapshot = updated
        // Serial writes preserve the order of partial inventory updates.
        let cache = cache
        let snapshotToSave = updated
        cacheQueue.async {
            do {
                try cache.save(snapshotToSave)
            } catch {
                AppLog.warn("Could not save model cache: \(error.localizedDescription)")
            }
        }
    }

    private func finishRefresh() {
        guard !isRefreshingInstalled && !isRefreshingCatalog else { return }
        if refreshPending {
            refreshPending = false
            refresh()
        }
    }
}
