import XCTest
@testable import ApplePodcastsTranscriberCore

final class DownloadedEpisodeDeleterTests: XCTestCase {
    func testDeleteRemovesProvidedAudioFilesOnly() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first.m4a")
        let second = root.appendingPathComponent("second.mp3")
        let unrelated = root.appendingPathComponent("notes.txt")

        try Data("audio".utf8).write(to: first)
        try Data("audio".utf8).write(to: second)
        try Data("notes".utf8).write(to: unrelated)

        let result = DownloadedEpisodeDeleter().delete([
            AudioFile(url: first, byteSize: 5),
            AudioFile(url: second, byteSize: 5)
        ])

        XCTAssertEqual(Set(result.deletedURLs), Set([first, second]))
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
