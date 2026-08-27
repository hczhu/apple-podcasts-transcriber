import Foundation
import SQLite3

public struct ShowNotes: Equatable {
    public let podcastTitle: String?
    public let episodeTitle: String?
    public let itemDescription: String?

    public init(podcastTitle: String?, episodeTitle: String?, itemDescription: String?) {
        self.podcastTitle = podcastTitle
        self.episodeTitle = episodeTitle
        self.itemDescription = itemDescription
    }

    public var isEmpty: Bool {
        podcastTitle == nil && episodeTitle == nil && itemDescription == nil
    }
}

public protocol ShowNotesReading {
    func showNotes(for episode: PodcastEpisode, libraryURL: URL) -> ShowNotes?
}

/// Reads episode show notes from the Apple Podcasts Core Data store
/// (`<library>/Documents/MTLibrary.sqlite`). The store keeps an episode row
/// after its audio file is deleted, so lookups still work post-transcription.
public struct MTLibraryShowNotesReader: ShowNotesReading {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func showNotes(for episode: PodcastEpisode, libraryURL: URL) -> ShowNotes? {
        let databaseURL = AppDefaults.libraryDatabaseURL(libraryRoot: libraryURL)
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        guard let database = open(databaseURL) else { return nil }
        defer { sqlite3_close(database) }

        // ZASSETURL stores the percent-encoded file:// URL of the downloaded audio.
        let fileName = episode.audioFile.url.lastPathComponent
        let encodedFileName = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName

        if let notes = query(database, sql: Self.assetURLQuery, argument: "%\(encodedFileName)") {
            return notes
        }

        return query(database, sql: Self.titleQuery, argument: episode.episodeName)
    }

    private static let selectClause = """
    SELECT p.ZTITLE, e.ZTITLE, e.ZITEMDESCRIPTIONWITHOUTHTML, e.ZITEMDESCRIPTION
    FROM ZMTEPISODE e
    LEFT JOIN ZMTPODCAST p ON p.Z_PK = e.ZPODCAST
    """

    private static let assetURLQuery = selectClause + """

    WHERE e.ZASSETURL LIKE ?1
    LIMIT 1
    """

    private static let titleQuery = selectClause + """

    WHERE e.ZTITLE = ?1 COLLATE NOCASE
    ORDER BY (e.ZITEMDESCRIPTIONWITHOUTHTML IS NULL), e.ZPUBDATE DESC
    LIMIT 1
    """

    /// Opens the store read-only. Podcasts keeps it in WAL mode and may hold a
    /// lock, so fall back to `immutable=1`, which ignores the -wal/-shm sidecars.
    private func open(_ databaseURL: URL) -> OpaquePointer? {
        let path = databaseURL.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? databaseURL.path

        for parameters in ["mode=ro", "mode=ro&immutable=1"] {
            var handle: OpaquePointer?
            let status = sqlite3_open_v2(
                "file:\(path)?\(parameters)",
                &handle,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
                nil
            )

            if status == SQLITE_OK, handle != nil {
                return handle
            }

            if let handle { sqlite3_close(handle) }
        }

        return nil
    }

    private func query(_ database: OpaquePointer, sql: String, argument: String) -> ShowNotes? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, argument, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let notes = ShowNotes(
            podcastTitle: text(statement, 0),
            episodeTitle: text(statement, 1),
            itemDescription: text(statement, 2) ?? text(statement, 3)
        )

        return notes.isEmpty ? nil : notes
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        let string = String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }
}
