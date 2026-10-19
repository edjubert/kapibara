import XCTest
@testable import Kapibara

/// The log parser must extract per-request stats from real
/// `serve-PORT.log` lines and ignore non-chat lines.
final class ActivityLogTests: XCTestCase {
    func testParsesChatLines() {
        let log = """
        [kapitsa] engine ready: qwen3.8-27b, context 131072, 4 slots
        [kapitsa] listening on http://127.0.0.1:8000
        [kapitsa] chat: prompt 4069 (cached 0) in 24285 ms (+1.9 ms template/tokenize; last chunk: encoded by 0.6 ms, GPU start +11756.7 ms, GPU 12527.4 ms, wake +0.1 ms), 8 tokens in 527 ms (13.3 tok/s), stop, 1.75 tok/cycle; slot 1, waited 0 ms for it
        [kapitsa] history: prefilled 127 tokens of the rendered reply (from 4059) in 885 ms
        [kapitsa] chat: prompt 4243 (cached 4059) in 1260 ms (+433.5 ms template/tokenize; last chunk: encoded by 0.3 ms, GPU start +27.5 ms, GPU 1232.1 ms, wake +0.2 ms), 127 tokens in 3038 ms (41.5 tok/s), stop, 3.07 tok/cycle
        [kapitsa] chat: prompt 4406 (cached 4369) in 666 ms (+2.0 ms template/tokenize; last chunk: encoded by 0.6 ms, GPU start +385.1 ms, GPU 279.8 ms, wake +0.2 ms), 74 tokens in 1179 ms (61.9 tok/s), tool_calls, 4.56 tok/cycle
        [kapitsa] chat: prompt 63294 (cached 62968) in 4045 ms (+9.6 ms template/tokenize; last chunk: encoded by 0.2 ms, GPU start +74.5 ms, GPU 3969.8 ms, wake +0.3 ms), 1753 tokens in 48378 ms (36.2 tok/s), cancelled, 4.50 tok/cycle
        [kapitsa] chat: prompt 54 (cached 0) in 18446 ms (+40.5 ms template/tokenize; last chunk: encoded by 3.5 ms, GPU start +18044.8 ms, GPU 397.9 ms, wake +0.2 ms), 4 tokens in 221 ms (13.6 tok/s), length, 3.00 tok/cycle
        """
        let entries = ActivityLog.parse(log)
        XCTAssertEqual(entries.count, 5)

        XCTAssertEqual(entries[0].promptTokens, 4069)
        XCTAssertEqual(entries[0].cachedTokens, 0)
        XCTAssertEqual(entries[0].prefillMs, 24285)
        XCTAssertEqual(entries[0].outputTokens, 8)
        XCTAssertEqual(entries[0].generationMs, 527)
        XCTAssertEqual(entries[0].tokPerSec, 13.3, accuracy: 0.01)
        XCTAssertEqual(entries[0].finishReason, "stop")

        XCTAssertEqual(entries[1].cachedTokens, 4059)
        XCTAssertEqual(entries[1].tokPerSec, 41.5, accuracy: 0.01)

        XCTAssertEqual(entries[2].finishReason, "tool_calls")
        XCTAssertEqual(entries[3].finishReason, "cancelled")
        XCTAssertEqual(entries[4].finishReason, "length")
    }

    func testIgnoresNonChatLines() {
        let log = """
        [kapitsa] GPU: Apple M3 Max, 30 cores
        [kapitsa] memory: 20.46 GB allocated
        [kapitsa] history: prefilled 127 tokens of the rendered reply (from 4059) in 885 ms
        [kapitsa] DFlash2: prewarmed 84 pipelines in 2 ms
        """
        XCTAssertTrue(ActivityLog.parse(log).isEmpty)
    }

    func testEmptyLog() {
        XCTAssertTrue(ActivityLog.parse("").isEmpty)
    }

    func testSummary() {
        let entries = [
            ActivityEntry(promptTokens: 1000, cachedTokens: 0, prefillMs: 100, outputTokens: 50, generationMs: 500, tokPerSec: 100, finishReason: "stop"),
            ActivityEntry(promptTokens: 2000, cachedTokens: 500, prefillMs: 300, outputTokens: 150, generationMs: 1500, tokPerSec: 100, finishReason: "stop"),
        ]
        let summary = ActivitySummary.compute(entries)
        XCTAssertEqual(summary.requestCount, 2)
        XCTAssertEqual(summary.totalPromptTokens, 3000)
        XCTAssertEqual(summary.totalOutputTokens, 200)
        XCTAssertEqual(summary.avgTokPerSec, 100, accuracy: 0.01)
        XCTAssertEqual(summary.avgPrefillMs, 200, accuracy: 0.01)
    }

    func testEmptySummary() {
        let summary = ActivitySummary.compute([])
        XCTAssertEqual(summary.requestCount, 0)
        XCTAssertEqual(summary.totalPromptTokens, 0)
        XCTAssertEqual(summary.avgTokPerSec, 0)
    }
}
