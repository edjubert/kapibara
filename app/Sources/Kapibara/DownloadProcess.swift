import Foundation

/// Owns the `kapitsa pull` child processes the app starts. One download
/// at a time: a second `start` while one is running is refused.
final class DownloadProcess {
    private var process: Process?
    private let lock = NSLock()

    /// The model currently downloading, nil when idle.
    private(set) var currentModel: String?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    /// Spawns `kapitsa pull <model>`. Throws `alreadyRunning` when a
    /// download is already in flight.
    func start(model: String) throws {
        lock.lock()
        if process?.isRunning == true {
            lock.unlock()
            throw DownloadError.alreadyRunning
        }
        lock.unlock()

        let child = try KapitsaCLI.pull(model)

        lock.lock()
        process = child
        currentModel = model
        lock.unlock()

        // Reap the process on a background queue so `isRunning` stays
        // accurate and the model list refreshes when it ends.
        DispatchQueue.global(qos: .background).async { [weak self] in
            child.waitUntilExit()
            DispatchQueue.main.async {
                guard let self else { return }
                self.lock.lock()
                if self.process === child {
                    self.process = nil
                    self.currentModel = nil
                }
                self.lock.unlock()
                NotificationCenter.default.post(
                    name: .downloadFinished,
                    object: nil,
                    userInfo: ["exitCode": child.terminationStatus]
                )
            }
        }
    }

    /// Cancels the running download (SIGINT: kapitsa keeps the parts
    /// already fetched and resumes on the next pull).
    func cancel() {
        lock.lock()
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        child.interrupt()
    }
}

enum DownloadError: Error {
    case alreadyRunning
}

extension NSNotification.Name {
    /// Posted on the main thread when a download process exits.
    static let downloadFinished = NSNotification.Name("Kapibara.downloadFinished")
}
