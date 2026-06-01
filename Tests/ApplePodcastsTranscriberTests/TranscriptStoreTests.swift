import XCTest
@testable import ApplePodcastsTranscriberCore

final class TranscriptStoreTests: XCTestCase {
    func testSafeFilenameUsesOnlyEpisodeName() {
        XCTAssertEqual(
            TranscriptStore.safeFilename(for: " My Favorite Episode: Part 1 / Bonus "),
            "My Favorite Episode- Part 1 - Bonus.txt"
        )
    }

    func testWriteCreatesTextFileNamedAfterEpisodeName() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TranscriptStore(outputDirectory: root.appendingPathComponent("Transcripts"))
        let outputURL = try store.write("Hello transcript", for: "episode one")

        XCTAssertEqual(outputURL.lastPathComponent, "episode one.txt")
        XCTAssertEqual(try String(contentsOf: outputURL), "Hello transcript")
        XCTAssertTrue(store.transcriptExists(for: "episode one"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
