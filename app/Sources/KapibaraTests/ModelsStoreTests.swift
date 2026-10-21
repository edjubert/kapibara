import XCTest
@testable import Kapibara

final class ModelsStoreTests: XCTestCase {
    private var directory: URL!
    private var cache: ModelsCache!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kapibara-models-\(UUID().uuidString)")
        cache = ModelsCache(url: directory.appendingPathComponent("nested/models.json"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testMissingCacheIsEmpty() throws {
        XCTAssertNil(try cache.load())
    }

    func testCacheRoundTripAndReplacement() throws {
        let original = sampleSnapshot()
        try cache.save(original)
        XCTAssertEqual(try cache.load(), original)

        var replacement = original
        replacement.installedModels = []
        replacement.installedUpdatedAt = Date(timeIntervalSince1970: 2_000)
        try cache.save(replacement)
        XCTAssertEqual(try cache.load(), replacement)
    }

    func testCorruptCacheDoesNotPreventStartup() throws {
        try cache.save(sampleSnapshot())
        try Data("{broken".utf8).write(to: cache.url)
        XCTAssertThrowsError(try cache.load())
        let store = ModelsStore(cache: cache)
        XCTAssertEqual(store.snapshot, ModelsSnapshot())
        XCTAssertFalse(store.isRefreshingInstalled)
        XCTAssertFalse(store.isRefreshingCatalog)
    }

    func testUnsupportedCacheVersionIsRejected() throws {
        var snapshot = sampleSnapshot()
        snapshot.version = 2
        try cache.save(snapshot)
        XCTAssertThrowsError(try cache.load())
        XCTAssertEqual(ModelsStore(cache: cache).snapshot, ModelsSnapshot())
    }

    func testStartupRestoresInventoryWithoutRunningCLI() throws {
        let snapshot = sampleSnapshot()
        try cache.save(snapshot)
        let store = ModelsStore(
            cache: cache,
            listModels: {
                XCTFail("Startup must restore the cache before querying installed models")
                return []
            },
            doctorReport: {
                XCTFail("Startup must restore the cache before running doctor")
                throw ProbeError.failed
            }
        )
        XCTAssertEqual(store.snapshot, snapshot)
    }

    func testInstalledModelsAppearBeforeSlowCatalog() throws {
        let models = [sampleModel()]
        let report = sampleReport()
        let doctorGate = DispatchSemaphore(value: 0)
        defer { doctorGate.signal() }
        let store = ModelsStore(
            cache: cache,
            listModels: { models },
            doctorReport: {
                _ = doctorGate.wait(timeout: .now() + 5)
                return report
            }
        )
        store.refresh()
        waitUntil { !store.isRefreshingInstalled }
        XCTAssertEqual(store.snapshot.installedModels, models)
        XCTAssertTrue(store.snapshot.catalogVariants.isEmpty)
        XCTAssertTrue(store.isRefreshingCatalog)

        // Even the partial result must survive a restart while doctor runs.
        waitUntil { (try? self.cache.load())?.installedModels == models }
        doctorGate.signal()
        waitUntil { !store.isRefreshingCatalog }
        XCTAssertEqual(store.snapshot.catalogVariants, report.catalogVariants)
        XCTAssertEqual(store.snapshot.doctorModels, report.models)
        waitUntil { (try? self.cache.load())?.catalogVariants == report.catalogVariants }
    }

    func testSuccessfulListPreservesCachedCatalogWhenDoctorFails() throws {
        let original = sampleSnapshot()
        try cache.save(original)
        let models = [sampleModel(name: "new-model:4bit")]
        let store = ModelsStore(
            cache: cache,
            listModels: { models },
            doctorReport: { throw ProbeError.failed }
        )
        store.refresh()
        waitUntil { !store.isRefreshingInstalled && !store.isRefreshingCatalog }
        XCTAssertNotNil(store.refreshError)
        XCTAssertEqual(store.snapshot.installedModels, models)
        XCTAssertEqual(store.snapshot.catalogVariants, original.catalogVariants)
        XCTAssertEqual(store.snapshot.doctorModels, original.doctorModels)
        XCTAssertEqual(store.snapshot.catalogUpdatedAt, original.catalogUpdatedAt)
        waitUntil { (try? self.cache.load())?.installedModels == models }
        XCTAssertEqual(try cache.load()?.catalogVariants, original.catalogVariants)
    }

    func testFailedRefreshKeepsEntireCache() throws {
        let original = sampleSnapshot()
        try cache.save(original)
        let store = ModelsStore(
            cache: cache,
            listModels: { throw ProbeError.failed },
            doctorReport: { throw ProbeError.failed }
        )
        store.refresh()
        waitUntil { !store.isRefreshingInstalled && !store.isRefreshingCatalog }
        XCTAssertNotNil(store.refreshError)
        XCTAssertEqual(store.snapshot, original)
        XCTAssertEqual(try cache.load(), original)
    }

    func testRequestsDuringRefreshAreCoalesced() throws {
        let counter = Counter()
        let doctorGate = DispatchSemaphore(value: 0)
        defer { doctorGate.signal() }
        let report = sampleReport()
        let store = ModelsStore(
            cache: cache,
            listModels: { [] },
            doctorReport: {
                let call = counter.increment()
                if call == 1 { _ = doctorGate.wait(timeout: .now() + 5) }
                return DoctorReport(
                    chip: report.chip, gpuCores: report.gpuCores,
                    ramBytes: report.ramBytes, macos: report.macos,
                    memoryBudgetBytes: report.memoryBudgetBytes, models: [],
                    catalogVariants: [CatalogVariant(
                        model: "catalog-\(call)", variant: "4bit", fits: true,
                        planned: true, chosen: true, isDefault: true
                    )]
                )
            }
        )
        store.refresh()
        store.refresh()
        store.refresh()
        waitUntil { counter.value == 1 && !store.isRefreshingInstalled }
        XCTAssertTrue(store.isRefreshingCatalog)
        doctorGate.signal()
        waitUntil {
            counter.value == 2 && !store.isRefreshingInstalled && !store.isRefreshingCatalog
        }
        XCTAssertEqual(counter.value, 2)
        waitUntil { (try? self.cache.load())?.catalogVariants.first?.model == "catalog-2" }
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping () -> Bool
    ) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate() },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed, file: file, line: line)
    }

    private func sampleModel(name: String = "qwen3.8-27b:4bit") -> InstalledModel {
        InstalledModel(
            name: name, variant: "4bit", dir: "/models/\(name)", repo: nil,
            commit: nil, complete: true, bytes: 20_169_260_357, includes: []
        )
    }

    private func sampleReport() -> DoctorReport {
        DoctorReport(
            chip: "Apple M3 Max", gpuCores: 30, ramBytes: 38_654_705_664,
            macos: "26.5", memoryBudgetBytes: 30_198_988_800,
            models: [DoctorModel(
                dir: "/models/qwen3.8-27b:4bit", starts: true, fitsFullContext: true,
                kvTokensInBudget: 131_072, contextLimit: 131_072,
                defaultContext: 90_112, decoding: "DFlash",
                decodeTpsEstimate: 50, prefillTpsEstimateGpu: 1_000
            )],
            catalogVariants: [CatalogVariant(
                model: "qwen3.8-27b", variant: "4bit", fits: true,
                planned: true, chosen: true, isDefault: true
            )]
        )
    }

    private func sampleSnapshot() -> ModelsSnapshot {
        let report = sampleReport()
        return ModelsSnapshot(
            installedModels: [sampleModel()],
            catalogVariants: report.catalogVariants,
            doctorModels: report.models,
            installedUpdatedAt: Date(timeIntervalSince1970: 1_000),
            catalogUpdatedAt: Date(timeIntervalSince1970: 1_001)
        )
    }

    private enum ProbeError: Error { case failed }

    private final class Counter {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }
}
