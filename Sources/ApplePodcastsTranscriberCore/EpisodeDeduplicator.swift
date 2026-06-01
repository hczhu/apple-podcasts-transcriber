import Foundation

public struct PodcastEpisodeGroup: Equatable {
    public let representativeEpisode: PodcastEpisode
    public let episodes: [PodcastEpisode]

    public init(representativeEpisode: PodcastEpisode, episodes: [PodcastEpisode]) {
        self.representativeEpisode = representativeEpisode
        self.episodes = episodes
    }

    public var duplicateCount: Int {
        max(0, episodes.count - 1)
    }

    public var allAudioFiles: [AudioFile] {
        episodes.map(\.audioFile)
    }
}

public enum EpisodeDeduplicator {
    public static func groupByDateAndTitle(_ episodes: [PodcastEpisode]) -> [PodcastEpisodeGroup] {
        var groupsByKey: [EpisodeGroupKey: Int] = [:]
        var groups: [PodcastEpisodeGroup] = []

        for episode in episodes {
            let key = EpisodeGroupKey(episode: episode)
            if let index = groupsByKey[key] {
                var existing = groups[index]
                existing = PodcastEpisodeGroup(
                    representativeEpisode: existing.representativeEpisode,
                    episodes: existing.episodes + [episode]
                )
                groups[index] = existing
                continue
            }

            groupsByKey[key] = groups.count
            groups.append(PodcastEpisodeGroup(
                representativeEpisode: episode,
                episodes: [episode]
            ))
        }

        return groups
    }
}

private struct EpisodeGroupKey: Hashable {
    let normalizedTitle: String
    let dayString: String?

    init(episode: PodcastEpisode) {
        normalizedTitle = episode.episodeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if let date = episode.episodeDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            dayString = formatter.string(from: date)
        } else {
            dayString = nil
        }
    }
}
