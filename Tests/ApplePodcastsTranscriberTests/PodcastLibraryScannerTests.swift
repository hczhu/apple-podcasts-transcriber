import XCTest
@testable import ApplePodcastsTranscriberCore

final class PodcastLibraryScannerTests: XCTestCase {
    func testScanReturnsSupportedAudioFilesSortedByPath() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let first = root.appendingPathComponent("b episode.mp3")
        let second = nested.appendingPathComponent("a episode.m4a")
        let ignored = root.appendingPathComponent("notes.txt")

        try Data("audio".utf8).write(to: first)
        try Data("audio".utf8).write(to: second)
        try Data("notes".utf8).write(to: ignored)

        let files = try PodcastLibraryScanner().scan(root)

        XCTAssertEqual(
            Set(files.map { $0.url.resolvingSymlinksInPath() }),
            Set([second, first].map { $0.resolvingSymlinksInPath() })
        )
        XCTAssertEqual(files.map(\.byteSize), [5, 5])
        XCTAssertNotNil(files.first?.fallbackEpisodeDate)
    }

    func testScanThrowsForUnreadableDirectory() {
        let missing = URL(fileURLWithPath: "/tmp/apple-podcasts-transcriber-missing-\(UUID().uuidString)")

        XCTAssertThrowsError(try PodcastLibraryScanner().scan(missing)) { error in
            XCTAssertEqual(
                error as? PodcastLibraryScannerError,
                .unreadableDirectory(missing.path)
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
