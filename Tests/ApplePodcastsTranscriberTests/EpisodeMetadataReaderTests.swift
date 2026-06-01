import XCTest
@testable import ApplePodcastsTranscriberCore

final class EpisodeMetadataReaderTests: XCTestCase {
    func testUsesAudioMetadataTitleAndDateBeforeSpotlight() throws {
        let audioDate = Date(timeIntervalSince1970: 1_000)
        let spotlightDate = Date(timeIntervalSince1970: 789)
        let audioFile = AudioFile(
            url: URL(fileURLWithPath: "/tmp/OpaqueFileName.m4a"),
            byteSize: 10,
            creationDate: Date(timeIntervalSince1970: 123)
        )

        let reader = FileEpisodeMetadataReader(
            audioMetadataReader: StubAudioMetadataReader(
                metadata: AudioMetadata(title: "Embedded Episode Title", creationDate: audioDate)
            ),
            spotlightMetadataReader: StubSpotlightMetadataReader(
                metadata: SpotlightMetadata(
                    title: "Spotlight Episode Name",
                    contentCreationDate: spotlightDate
                )
            )
        )

        let metadata = try reader.readMetadata(from: audioFile)

        XCTAssertEqual(metadata.episodeName, "Embedded Episode Title")
        XCTAssertEqual(metadata.episodeDate, audioDate)
    }

    func testUsesSpotlightTitleAndDateWhenAvailable() throws {
        let spotlightDate = Date(timeIntervalSince1970: 789)
        let audioFile = AudioFile(
            url: URL(fileURLWithPath: "/tmp/OpaqueFileName.m4a"),
            byteSize: 10,
            creationDate: Date(timeIntervalSince1970: 123)
        )

        let reader = FileEpisodeMetadataReader(
            audioMetadataReader: StubAudioMetadataReader(
                metadata: AudioMetadata(title: nil, creationDate: nil)
            ),
            spotlightMetadataReader: StubSpotlightMetadataReader(
                metadata: SpotlightMetadata(
                    title: "Real Episode Name",
                    contentCreationDate: spotlightDate
                )
            )
        )

        let metadata = try reader.readMetadata(from: audioFile)

        XCTAssertEqual(metadata.episodeName, "Real Episode Name")
        XCTAssertEqual(metadata.episodeDate, spotlightDate)
    }

    func testFallsBackToFileNameAndFileDate() throws {
        let date = Date(timeIntervalSince1970: 123)
        let audioFile = AudioFile(
            url: URL(fileURLWithPath: "/tmp/Episode Name.m4a"),
            byteSize: 10,
            creationDate: date,
            modificationDate: Date(timeIntervalSince1970: 456)
        )

        let reader = FileEpisodeMetadataReader(
            audioMetadataReader: StubAudioMetadataReader(
                metadata: AudioMetadata(title: nil, creationDate: nil)
            ),
            spotlightMetadataReader: StubSpotlightMetadataReader(
                metadata: SpotlightMetadata(title: nil, contentCreationDate: nil)
            )
        )

        let metadata = try reader.readMetadata(from: audioFile)

        XCTAssertEqual(metadata.episodeName, "Episode Name")
        XCTAssertEqual(metadata.episodeDate, date)
    }
}

private struct StubAudioMetadataReader: AudioMetadataReading {
    let metadata: AudioMetadata

    func readMetadata(at url: URL) throws -> AudioMetadata {
        metadata
    }
}

private struct StubSpotlightMetadataReader: SpotlightMetadataReading {
    let metadata: SpotlightMetadata

    func readMetadata(at url: URL) throws -> SpotlightMetadata {
        metadata
    }
}
