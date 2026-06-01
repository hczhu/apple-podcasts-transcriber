import XCTest
@testable import ApplePodcastsTranscriberCore

final class EpisodeDeduplicatorTests: XCTestCase {
    func testGroupByDateAndTitleKeepsOneRepresentativePerDayAndTitle() {
        let kept = PodcastEpisode(
            audioFile: AudioFile(url: URL(fileURLWithPath: "/tmp/first.m4a"), byteSize: 1),
            episodeName: "Same Episode Title",
            episodeDate: Date(timeIntervalSince1970: 2)
        )
        let skipped = PodcastEpisode(
            audioFile: AudioFile(url: URL(fileURLWithPath: "/tmp/second.mp3"), byteSize: 1),
            episodeName: "Same Episode Title",
            episodeDate: Date(timeIntervalSince1970: 1)
        )
        let unique = PodcastEpisode(
            audioFile: AudioFile(url: URL(fileURLWithPath: "/tmp/third.mp3"), byteSize: 1),
            episodeName: "Different Episode",
            episodeDate: Date(timeIntervalSince1970: 0)
        )

        let result = EpisodeDeduplicator.groupByDateAndTitle([kept, skipped, unique])

        XCTAssertEqual(result.map(\.representativeEpisode), [kept, unique])
        XCTAssertEqual(result[0].episodes, [kept, skipped])
        XCTAssertEqual(result[0].duplicateCount, 1)
    }

    func testGroupByDateAndTitleDoesNotMergeDifferentDates() {
        let first = PodcastEpisode(
            audioFile: AudioFile(url: URL(fileURLWithPath: "/tmp/first.m4a"), byteSize: 1),
            episodeName: "Same Episode Title",
            episodeDate: Date(timeIntervalSince1970: 2)
        )
        let second = PodcastEpisode(
            audioFile: AudioFile(url: URL(fileURLWithPath: "/tmp/second.mp3"), byteSize: 1),
            episodeName: "Same Episode Title",
            episodeDate: Date(timeIntervalSince1970: 100000)
        )

        let result = EpisodeDeduplicator.groupByDateAndTitle([first, second])

        XCTAssertEqual(result.map(\.representativeEpisode), [first, second])
    }
}
