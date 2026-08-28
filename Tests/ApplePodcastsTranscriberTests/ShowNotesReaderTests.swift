import SQLite3
import XCTest
@testable import ApplePodcastsTranscriberCore

final class ShowNotesReaderTests: XCTestCase {
    private var libraryURL: URL!

    override func setUpWithError() throws {
        libraryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("show-notes-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: libraryURL.appendingPathComponent("Documents"),
            withIntermediateDirectories: true
        )
        try makeLibraryDatabase()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryURL)
    }

    func testMatchesEpisodeByDownloadedAudioFileName() {
        let notes = showNotes(fileName: "40B78782-CAFE.mp3", episodeName: "Unrelated Metadata Title")

        XCTAssertEqual(notes?.podcastTitle, "Asianometry")
        XCTAssertEqual(notes?.episodeTitle, "SK hynix and the HBM Revolution")
        XCTAssertEqual(notes?.itemDescription, "How SK hynix became an AI memory titan.")
    }

    func testMatchesFileNameNeedingPercentEncoding() {
        let notes = showNotes(fileName: "Episode With Spaces.mp3", episodeName: "no match")
        XCTAssertEqual(notes?.episodeTitle, "Spaced Out")
    }

    func testFallsBackToExactEpisodeTitle() {
        let notes = showNotes(fileName: "not-in-library.mp3", episodeName: "SK hynix and the HBM Revolution")
        XCTAssertEqual(notes?.podcastTitle, "Asianometry")
    }

    /// Feeds commonly prefix the ID3 title with the show name.
    func testFallsBackToTitlePrefixedWithShowName() {
        let notes = showNotes(
            fileName: "not-in-library.mp3",
            episodeName: "\u{7845}\u{8C37}101: E250\u{FF5C}mRNA and Moderna"
        )
        XCTAssertEqual(notes?.podcastTitle, "\u{7845}\u{8C37}101")
        XCTAssertEqual(notes?.itemDescription, "Moderna phase three results.")
    }

    func testShortStoredTitlesDoNotMatchBySuffix() {
        let notes = showNotes(fileName: "not-in-library.mp3", episodeName: "Today we discuss AI")
        XCTAssertNil(notes)
    }

    func testFallsBackToHTMLDescriptionWhenPlainTextIsMissing() {
        let notes = showNotes(fileName: "html-only.mp3", episodeName: "no match")
        XCTAssertEqual(notes?.itemDescription, "<p>Only markup here.</p>")
    }

    func testReturnsNilWhenNothingMatches() {
        XCTAssertNil(showNotes(fileName: "not-in-library.mp3", episodeName: "No Such Episode Anywhere"))
    }

    func testReturnsNilWhenDatabaseIsAbsent() {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("show-notes-empty-\(UUID().uuidString)")
        XCTAssertNil(showNotes(fileName: "any.mp3", episodeName: "any", libraryURL: empty))
    }

    // MARK: - Helpers

    private func showNotes(fileName: String, episodeName: String, libraryURL: URL? = nil) -> ShowNotes? {
        let episode = PodcastEpisode(
            audioFile: AudioFile(
                url: URL(fileURLWithPath: "/tmp/Library/Cache").appendingPathComponent(fileName),
                byteSize: 0
            ),
            episodeName: episodeName,
            episodeDate: nil
        )

        return MTLibraryShowNotesReader().showNotes(
            for: episode,
            libraryURL: libraryURL ?? self.libraryURL
        )
    }

    private func makeLibraryDatabase() throws {
        let path = AppDefaults.libraryDatabaseURL(libraryRoot: libraryURL).path
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }

        let statements = """
        CREATE TABLE ZMTPODCAST (Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR);
        CREATE TABLE ZMTEPISODE (
            Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZTITLE VARCHAR, ZASSETURL VARCHAR,
            ZITEMDESCRIPTIONWITHOUTHTML VARCHAR, ZITEMDESCRIPTION VARCHAR, ZPUBDATE TIMESTAMP
        );
        INSERT INTO ZMTPODCAST VALUES (1, 'Asianometry'), (2, '\u{7845}\u{8C37}101');
        INSERT INTO ZMTEPISODE VALUES (
            1, 1, 'SK hynix and the HBM Revolution',
            'file:///Users/x/Library/Cache/40B78782-CAFE.mp3',
            'How SK hynix became an AI memory titan.', NULL, 1
        );
        INSERT INTO ZMTEPISODE VALUES (
            2, 2, 'E250\u{FF5C}mRNA and Moderna', NULL,
            'Moderna phase three results.', NULL, 2
        );
        INSERT INTO ZMTEPISODE VALUES (
            3, 1, 'Spaced Out',
            'file:///Users/x/Library/Cache/Episode%20With%20Spaces.mp3',
            'Notes for the spaced file.', NULL, 3
        );
        INSERT INTO ZMTEPISODE VALUES (
            4, 1, 'HTML Only', 'file:///Users/x/Library/Cache/html-only.mp3',
            NULL, '<p>Only markup here.</p>', 4
        );
        INSERT INTO ZMTEPISODE VALUES (5, 1, 'AI', NULL, 'Too short to match by suffix.', NULL, 5);
        """

        var error: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(database, statements, nil, nil, &error), SQLITE_OK)
        if let error { sqlite3_free(error) }
    }
}
