import Foundation

// Decodable mirrors of `kapitsa` JSON output.
// Run: /usr/bin/env kapitsa list --json, kapitsa doctor --json,
//      kapitsa pull M --dry-run --json

/// One downloaded model, from `kapitsa list --json`.
struct InstalledModel: Codable, Equatable, Identifiable {
    let name: String
    let variant: String
    let dir: String
    let repo: String?
    let commit: String?
    let complete: Bool
    let bytes: Int64
    let includes: [String]

    /// "qwen3.8-27b:4bit" -> id stable for SwiftUI lists.
    var id: String { name }

    /// Human-readable size, e.g. "20.2 GB".
    var sizeLabel: String { Self.formatBytes(bytes) }

    static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

/// One catalog model entry, from `kapitsa doctor --json`'s `models` array
/// (only the fields the UI shows).
struct DoctorModel: Codable, Equatable {
    let dir: String
    let starts: Bool
    let fitsFullContext: Bool
    let kvTokensInBudget: Int
    let contextLimit: Int
    let defaultContext: Int
    let decoding: String
    let decodeTpsEstimate: Double
    let prefillTpsEstimateGpu: Double

    enum CodingKeys: String, CodingKey {
        case dir, starts, decoding
        case fitsFullContext = "fits_full_context"
        case kvTokensInBudget = "kv_tokens_in_budget"
        case contextLimit = "context_limit"
        case defaultContext = "default_context"
        case decodeTpsEstimate = "decode_tps_estimate"
        case prefillTpsEstimateGpu = "prefill_tps_estimate_gpu"
    }
}

/// One catalog variant, from `kapitsa doctor --json`'s `catalog_variants`.
struct CatalogVariant: Codable, Equatable, Identifiable {
    let model: String
    let variant: String
    let fits: Bool
    let planned: Bool
    let chosen: Bool
    let isDefault: Bool

    /// "qwen3.8-27b:4bit" — the name `kapitsa pull` and `kapitsa list` use.
    var id: String { "\(model):\(variant)" }

    enum CodingKeys: String, CodingKey {
        case model, variant, fits, planned, chosen
        case isDefault = "default"
    }
}

/// This Mac, from `kapitsa doctor --json`.
struct DoctorReport: Codable, Equatable {
    let chip: String
    let gpuCores: Int
    let ramBytes: Int64
    let macos: String
    let memoryBudgetBytes: Int64
    let models: [DoctorModel]
    let catalogVariants: [CatalogVariant]

    enum CodingKeys: String, CodingKey {
        case chip
        case gpuCores = "gpu_cores"
        case ramBytes = "ram_bytes"
        case macos
        case memoryBudgetBytes = "memory_budget_bytes"
        case models
        case catalogVariants = "catalog_variants"
    }
}

/// What `kapitsa pull M --dry-run --json` resolves a model name to.
struct PullPlan: Codable, Equatable {
    let model: String
    let kind: String
    let id: String
    let dir: String
    let repo: String?
    let revision: String?
    let downloaded: Bool
    let variant: String?
    let quant: String?
    let companions: [Companion]

    struct Companion: Codable, Equatable {
        let kind: String
        let repo: String?
        let revision: String?
        let into: String?
    }
}

enum KapitsaError: Error {
    case processFailed(exitCode: Int32)
    case badJSON(String)
    case noBinary
}

/// Runs the kapitsa binary with the given arguments, returns stdout.
private func runKapitsa(arguments: [String]) throws -> Data {
    let process = Process()
    if let path = KapitsaCLI.candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["kapitsa"] + arguments
    }
    let out = Pipe()
    process.standardOutput = out
    process.standardError = Pipe() // keep the UI quiet on CLI diagnostics
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw KapitsaError.processFailed(exitCode: process.terminationStatus)
    }
    return data
}

/// Runs the kapitsa binary and decodes its JSON output.
enum KapitsaCLI {
    /// Candidate locations, tried in order. The preferred one is the copy
    /// embedded in the .app bundle by `make app` as `kapitsa-cli` (a name
    /// that does not collide with the app executable on case-insensitive
    /// APFS), which makes the installed app self-contained. GUI apps
    /// inherit a minimal PATH (no /opt/homebrew/bin), so explicit lookups
    /// are required for the fallbacks.
    static var candidates: [String] {
        [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/kapitsa-cli").path,
            NSHomeDirectory() + "/.local/bin/kapitsa",
            "/opt/homebrew/bin/kapitsa",
            "/usr/local/bin/kapitsa",
        ]
    }

    static var isInstalled: Bool {
        candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `kapitsa list --json`: the downloaded models.
    static func list() throws -> [InstalledModel] {
        let data = try runKapitsa(arguments: ["list", "--json"])
        return try decode([InstalledModel].self, from: data)
    }

    /// `kapitsa doctor --json`: this Mac and which models fit it.
    static func doctor() throws -> DoctorReport {
        let data = try runKapitsa(arguments: ["doctor", "--json"])
        return try decode(DoctorReport.self, from: data)
    }

    /// `kapitsa pull M --dry-run --json`: what a model name resolves to,
    /// without downloading.
    static func pullPlan(_ model: String) throws -> PullPlan {
        let data = try runKapitsa(arguments: ["pull", model, "--dry-run", "--json"])
        return try decode(PullPlan.self, from: data)
    }

    /// Spawns `kapitsa pull M` as a child process and returns it. The
    /// caller owns the process and can poll `isRunning` or wait on it.
    /// The download writes its progress to stdout, which is piped so a
    /// future progress UI can read it.
    static func pull(_ model: String) throws -> Process {
        let binary = candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let binary else { throw KapitsaError.noBinary }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: binary)
        child.arguments = ["pull", model]
        child.standardOutput = Pipe()
        child.standardError = Pipe()
        try child.run()
        return child
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // No keyDecodingStrategy: every snake_case JSON key has an
        // explicit CodingKey raw value, and convertFromSnakeCase would
        // break those explicit raw values.
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KapitsaError.badJSON(String(data: data, encoding: .utf8) ?? "<no data>")
        }
    }
}
