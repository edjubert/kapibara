import XCTest
@testable import Kapibara

/// The Decodable mirrors must match the real `kapitsa` JSON output.
/// Samples are captured from kapitsa 0.1.37 on an M3 Max.
final class DecodeTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        // Same decoder setup as KapitsaCLI.decode: no key strategy,
        // explicit CodingKey raw values carry the snake_case names.
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testInstalledModel() throws {
        let json = """
        [{
            "name": "qwen3.8-27b:4bit",
            "variant": "4bit",
            "dir": "/Users/x/.cache/kapitsa/models/qwen3.8-27b-4bit",
            "repo": "lmstudio-community/Qwen3.8-27B-MLX-4bit",
            "commit": "6067b15cf581666a4aecf6af3afaba4bb5efc20c",
            "complete": true,
            "bytes": 20169260357,
            "includes": ["MTP head", "DFlash2 drafter"]
        }]
        """
        let models = try decode([InstalledModel].self, json)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].name, "qwen3.8-27b:4bit")
        XCTAssertEqual(models[0].bytes, 20_169_260_357)
        XCTAssertTrue(models[0].complete)
        XCTAssertEqual(models[0].sizeLabel, "18.8 GB")
    }

    func testCatalogVariant() throws {
        let json = """
        {
            "chip": "Apple M3 Max",
            "gpu_cores": 30,
            "ram_bytes": 38654705664,
            "macos": "26.5",
            "memory_budget_bytes": 30198988800,
            "models": [],
            "catalog_variants": [
                {"model": "qwen3.5-4b", "variant": "4bit", "fits": true, "planned": true, "chosen": true, "default": true},
                {"model": "qwen3.8-27b", "variant": "6bit", "fits": false, "planned": true, "chosen": false, "default": false}
            ]
        }
        """
        let report = try decode(DoctorReport.self, json)
        XCTAssertEqual(report.catalogVariants.count, 2)
        XCTAssertEqual(report.catalogVariants[0].id, "qwen3.5-4b:4bit")
        XCTAssertTrue(report.catalogVariants[0].fits)
        XCTAssertTrue(report.catalogVariants[0].isDefault)
        XCTAssertFalse(report.catalogVariants[1].fits)
        XCTAssertFalse(report.catalogVariants[1].isDefault)
    }

    func testServedModel() throws {
        let json = """
        {"object": "list", "data": [{
            "id": "qwen3.8-27b",
            "object": "model",
            "display_name": "qwen3.8-27b",
            "context_length": 131072,
            "context_fit": 131072,
            "slots": 4
        }]}
        """
        let response = try decode(ModelsResponse.self, json)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].id, "qwen3.8-27b")
        XCTAssertEqual(response.data[0].slots, 4)
    }

    func testFormatBytes() {
        XCTAssertEqual(InstalledModel.formatBytes(0), "0 MB")
        XCTAssertEqual(InstalledModel.formatBytes(1_048_576), "1 MB")
        XCTAssertEqual(InstalledModel.formatBytes(20_169_260_357), "18.8 GB")
        XCTAssertEqual(InstalledModel.formatBytes(105_900_000_000), "98.6 GB")
    }
}
