import XCTest
@testable import Mac灵动岛

@MainActor
final class LyricsServiceTests: XCTestCase {

    /// Each parsed line as "seconds text"
    private func parse(_ lrc: String) -> [String] {
        LyricsService.parseLRC(lrc).map { String(format: "%.2f %@", $0.timeInSeconds, $0.line) }
    }

    func testTimestampsWithOneToThreeDecimals() {
        XCTAssertEqual(parse("[00:22.36]故事的小黄花"), ["22.36 故事的小黄花"], "LRCLIB writes hundredths")
        XCTAssertEqual(parse("[00:25.360]从出生那年就飘着"), ["25.36 从出生那年就飘着"], "NetEase often writes milliseconds")
        XCTAssertEqual(parse("[00:12.3]one digit"), ["12.30 one digit"])
        XCTAssertEqual(parse("[01:02:50]a colon before the fraction"), ["62.50 a colon before the fraction"])
    }

    func testALineWithSeveralTimestamps() {
        XCTAssertEqual(parse("[00:10.00][01:30.00]repeated chorus"), ["10.00 repeated chorus", "90.00 repeated chorus"],
                       "a chorus that comes back shares its line, and no timestamp is left in the text")
    }

    func testTagsAndEmptyLinesAreSkipped() {
        let lrc = "[ar:周杰伦]\n[ti:晴天]\n\n[00:40.00]\n\u{FEFF}[00:41.00]  the next line  "
        XCTAssertEqual(parse(lrc), ["41.00 the next line"])
    }

    func testLinesComeOutInTimeOrder() {
        XCTAssertEqual(parse("[00:20.00]second\n[00:10.00]first"), ["10.00 first", "20.00 second"])
    }
}
