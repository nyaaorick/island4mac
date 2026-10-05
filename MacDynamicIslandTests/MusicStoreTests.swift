import XCTest
@testable import MacDynamicIsland

@MainActor
final class MusicStoreTests: XCTestCase {

    private func makeStore() -> MusicStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MusicStoreTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return MusicStore(artworkFolder: folder)
    }

    private func state(title: String, playing: Bool = true, artwork: Data? = nil, app: String = "com.apple.Music") -> NowPlayingState {
        NowPlayingState(isPlaying: playing, playbackRate: playing ? 1 : 0, title: title, artist: "Artist", album: "",
                        duration: 200, position: 30, positionTimestamp: Date(timeIntervalSince1970: 1000), sourceApp: app,
                        artworkData: artwork)
    }

    func testTheSystemsNowPlayingBecomesMedia() throws {
        let store = makeStore()
        store.update(from: state(title: "Song"))
        let media = try XCTUnwrap(store.media)
        XCTAssertEqual(media.title, "Song")
        XCTAssertEqual(media.app, "com.apple.Music")
        XCTAssertEqual(media.elapsed, 30)
        XCTAssertEqual(media.at, 1000)
        XCTAssertEqual(media.duration, 200)
        XCTAssertEqual(media.artwork, .app("com.apple.Music"), "until artwork arrives, the app's icon")

        store.update(from: state(title: "Song", artwork: Data([1, 2, 3])))
        guard case .file(let path) = store.media?.artwork else { return XCTFail("the player's artwork is a file") }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data([1, 2, 3]))

        store.update(from: .idle)
        XCTAssertNil(store.media, "nothing plays")
    }

    func testPlainLyricsAreTrimmedLines() {
        XCTAssertEqual(MusicStore.plainLines("\n[00:01.00]One\nTwo\n\n").map(\.text), ["One", "Two"])
        XCTAssertTrue(MusicStore.plainLines("one").allSatisfy { $0.time == nil })
    }
}
