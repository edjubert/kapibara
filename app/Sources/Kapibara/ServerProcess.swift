import Foundation

/// Owns the `kapitsa serve` child process the app starts itself.
///
/// A server started outside the app (brew services, a terminal) is
/// detected by polling but never killed: `stop()` only terminates a
/// process this object spawned.
final class ServerProcess {
    private var process: Process?
    private let lock = NSLock()

    /// True when this object holds a live child process.
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    /// Spawns `kapitsa serve` on the given port, optionally pinned to a
    /// model and a context window (tokens). Replaces any child this
    /// object already holds.
    func start(port: Int, model: String?, context: Int? = nil) throws {
        stop()

        let binary = KapitsaCLI.candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let binary else { throw KapitsaError.noBinary }

        var arguments = ["serve", "--port", String(port)]
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        if let context, context > 0 {
            arguments += ["--context", String(context)]
        }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: binary)
        child.arguments = arguments
        // The server writes its own log to ~/.cache/kapitsa/logs/;
        // keep its stdout/stderr out of the app's face.
        child.standardOutput = nil
        child.standardError = nil

        try child.run()

        lock.lock()
        process = child
        lock.unlock()
    }

    /// Terminates the child process, if this object started one.
    func stop() {
        lock.lock()
        let child = process
        process = nil
        lock.unlock()

        guard let child, child.isRunning else { return }
        child.terminate()
        // Give it a moment to shut down cleanly, then force-kill.
        let deadline = Date().addingTimeInterval(3)
        while child.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if child.isRunning {
            child.interrupt()
        }
    }
}
