import Foundation

public enum EpisodeSorter {
    public static func newestFirst(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        episodes.sorted { lhs, rhs in
            switch (lhs.episodeDate, rhs.episodeDate) {
            case let (leftDate?, rightDate?):
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            let nameComparison = lhs.episodeName.localizedStandardCompare(rhs.episodeName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return lhs.audioFile.url.path.localizedStandardCompare(rhs.audioFile.url.path) == .orderedAscending
        }
    }
}
