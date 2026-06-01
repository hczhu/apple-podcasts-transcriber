import XCTest
@testable import ApplePodcastsTranscriberCore

final class TranscriptStoreTests: XCTestCase {
    func testSafeFilenameWithoutDate() {
        XCTAssertEqual(
            TranscriptStore.safeFilename(for: " My Favorite Episode: Part 1 / Bonus ", date: nil),
            "My Favorite Episode- Part 1 - Bonus.txt"
        )
    }

    func testSafeFilenameWithDate() {
        XCTAssertEqual(
            TranscriptStore.safeFilename(for: "The Big Episode", date: "2024-03-07"),
            "2024-03-07 - The Big Episode.txt"
        )
    }

    func testWriteCreatesTextFileNamedAfterEpisodeName() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TranscriptStore(outputDirectory: root.appendingPathComponent("Transcripts"))
        let outputURL = try store.write("Hello transcript", for: "episode one", date: nil)

        XCTAssertEqual(outputURL.lastPathComponent, "episode one.txt")
        XCTAssertEqual(try String(contentsOf: outputURL), "Hello transcript")
        XCTAssertTrue(store.transcriptExists(for: "episode one", date: nil))
    }

    func testWriteCreatesOutputDirectoryIfMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("a/b/c")
        let store = TranscriptStore(outputDirectory: nested)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
        _ = try store.write("text", for: "ep", date: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
