import Foundation

/// App log, one line per event, appended to `~/.kapibara/kapibara.log`.
/// Format: `[2026-10-20 10:55:00] [INFO] message`.
enum AppLog {
    private static let fileManager = FileManager.default

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// `~/.kapibara/kapibara.log`, creating the directory if needed.
    static var logFileURL: URL {
        let dir = NSHomeDirectory() + "/.kapibara"
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: dir).appendingPathComponent("kapibara.log")
    }

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    /// The last `count` non-empty lines of the log, oldest first.
    static func recentLines(_ count: Int = 50) -> [String] {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return Array(lines.suffix(count))
    }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(dateFormatter.string(from: Date()))] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let path = logFileURL.path
        if fileManager.fileExists(atPath: path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }
}
