import Foundation

/// One chat completion, parsed from a `serve-PORT.log` line.
struct ActivityEntry: Equatable, Identifiable {
    let promptTokens: Int
    let cachedTokens: Int
    let prefillMs: Double
    let outputTokens: Int
    let generationMs: Double
    let tokPerSec: Double
    let finishReason: String

    /// Stable id: the entry's position in the file, assigned by the parser.
    var id: Int { promptTokens &* 31 &+ outputTokens &* 17 &+ Int(tokPerSec) }
}

/// Parses `~/.cache/kapitsa/logs/serve-<port>.log` into per-request
/// entries. The log lines look like:
///
///   [kapitsa] chat: prompt 4069 (cached 0) in 24285 ms (+1.9 ms
///   template/tokenize; last chunk: ...), 8 tokens in 527 ms
///   (13.3 tok/s), stop, 1.75 tok/cycle; slot 1, ...
///
/// Only `chat:` lines are activity; startup banners, history prefills
/// and other lines are ignored.
enum ActivityLog {
    /// Matches one chat completion line. Capture groups:
    /// 1=prompt tokens, 2=cached tokens, 3=prefill ms, 4=output tokens,
    /// 5=generation ms, 6=tok/s, 7=finish reason.
    private static let linePattern = try! NSRegularExpression(pattern:
        #"chat: prompt (\d+) \(cached (\d+)\) in ([\d.]+) ms .*?, (\d+) tokens in ([\d.]+) ms \(([\d.]+) tok/s\), (\w+)"#
    )

    /// The log directory, honoring KAPITSA_HOME like the CLI does.
    static func logDirectory() -> URL {
        if let home = ProcessInfo.processInfo.environment["KAPITSA_HOME"] {
            return URL(fileURLWithPath: home).appendingPathComponent("logs")
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/kapitsa/logs")
    }

    /// Reads the log for `port` and returns the parsed entries, oldest
    /// first. Missing or unreadable log yields an empty list.
    static func entries(port: Int) -> [ActivityEntry] {
        let url = logDirectory().appendingPathComponent("serve-\(port).log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(text)
    }

    /// Parses the log text. Exposed for tests.
    static func parse(_ text: String) -> [ActivityEntry] {
        var entries: [ActivityEntry] = []
        for line in text.split(separator: "\n") {
            guard let entry = parseLine(String(line)) else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// One line, or nil when it is not a chat completion line.
    private static func parseLine(_ line: String) -> ActivityEntry? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = linePattern.firstMatch(in: line, range: range),
              match.numberOfRanges == 8
        else { return nil }

        func group(_ i: Int) -> String {
            guard let r = Range(match.range(at: i), in: line) else { return "" }
            return String(line[r])
        }

        guard let prompt = Int(group(1)),
              let cached = Int(group(2)),
              let prefill = Double(group(3)),
              let output = Int(group(4)),
              let genMs = Double(group(5)),
              let tps = Double(group(6))
        else { return nil }

        return ActivityEntry(
            promptTokens: prompt,
            cachedTokens: cached,
            prefillMs: prefill,
            outputTokens: output,
            generationMs: genMs,
            tokPerSec: tps,
            finishReason: group(7)
        )
    }
}

/// Aggregate stats over a set of activity entries.
struct ActivitySummary: Equatable {
    let requestCount: Int
    let totalPromptTokens: Int
    let totalOutputTokens: Int
    let avgTokPerSec: Double
    let avgPrefillMs: Double

    static func compute(_ entries: [ActivityEntry]) -> ActivitySummary {
        guard !entries.isEmpty else {
            return ActivitySummary(
                requestCount: 0,
                totalPromptTokens: 0,
                totalOutputTokens: 0,
                avgTokPerSec: 0,
                avgPrefillMs: 0
            )
        }
        let totalPrompt = entries.reduce(0) { $0 + $1.promptTokens }
        let totalOutput = entries.reduce(0) { $0 + $1.outputTokens }
        let avgTps = entries.reduce(0.0) { $0 + $1.tokPerSec } / Double(entries.count)
        let avgPrefill = entries.reduce(0.0) { $0 + $1.prefillMs } / Double(entries.count)
        return ActivitySummary(
            requestCount: entries.count,
            totalPromptTokens: totalPrompt,
            totalOutputTokens: totalOutput,
            avgTokPerSec: avgTps,
            avgPrefillMs: avgPrefill
        )
    }
}
