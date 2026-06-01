import XCTest
@testable import ApplePodcastsTranscriberCore

final class EpisodeSorterTests: XCTestCase {
    func testNewestFirstSortsDatedEpisodesBeforeOlderAndUndatedEpisodes() {
        let older = episode(name: "Older", date: Date(timeIntervalSince1970: 100))
        let newest = episode(name: "Newest", date: Date(timeIntervalSince1970: 300))
        let undated = episode(name: "Undated", date: nil)
        let middle = episode(name: "Middle", date: Date(timeIntervalSince1970: 200))

        let sorted = EpisodeSorter.newestFirst([older, newest, undated, middle])

        XCTAssertEqual(sorted.map(\.episodeName), ["Newest", "Middle", "Older", "Undated"])
    }

    func testUndatedEpisodesSortByName() {
        let beta = episode(name: "Beta", date: nil)
        let alpha = episode(name: "Alpha", date: nil)

        let sorted = EpisodeSorter.newestFirst([beta, alpha])

        XCTAssertEqual(sorted.map(\.episodeName), ["Alpha", "Beta"])
    }

    private func episode(name: String, date: Date?) -> PodcastEpisode {
        PodcastEpisode(
            audioFile: AudioFile(url: URL(fileURLWithPath: "/tmp/\(name).m4a"), byteSize: 0),
            episodeName: name,
            episodeDate: date
        )
    }
}
