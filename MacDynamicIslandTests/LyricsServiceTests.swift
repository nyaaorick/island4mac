import XCTest
@testable import MacDynamicIsland

@MainActor
final class LyricsServiceTests: XCTestCase {

    /// Each parsed line as "seconds text"
    private func parse(_ lrc: String) -> [String] {
        LyricsService.parseLRC(lrc).map { String(format: "%.2f %@", $0.timeInSeconds, $0.line) }
    }

    func testTimestampsWithOneToThreeDecimals() {
        XCTAssertEqual(parse("[00:22.36]little yellow flowers"), ["22.36 little yellow flowers"], "LRCLIB writes hundredths")
        XCTAssertEqual(parse("[00:25.360]drifting since the day we were born"), ["25.36 drifting since the day we were born"], "NetEase often writes milliseconds")
        XCTAssertEqual(parse("[00:12.3]one digit"), ["12.30 one digit"])
        XCTAssertEqual(parse("[01:02:50]a colon before the fraction"), ["62.50 a colon before the fraction"])
    }

    func testALineWithSeveralTimestamps() {
        XCTAssertEqual(parse("[00:10.00][01:30.00]repeated chorus"), ["10.00 repeated chorus", "90.00 repeated chorus"],
                       "a chorus that comes back shares its line, and no timestamp is left in the text")
    }

    func testTagsAndEmptyLinesAreSkipped() {
        let lrc = "[ar:Some Artist]\n[ti:Some Title]\n\n[00:40.00]\n\u{FEFF}[00:41.00]  the next line  "
        XCTAssertEqual(parse(lrc), ["41.00 the next line"])
    }

    func testLinesComeOutInTimeOrder() {
        XCTAssertEqual(parse("[00:20.00]second\n[00:10.00]first"), ["10.00 first", "20.00 second"])
    }
}
