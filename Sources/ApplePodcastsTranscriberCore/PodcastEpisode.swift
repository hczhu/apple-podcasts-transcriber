import Foundation

public struct PodcastEpisode: Equatable {
    public let audioFile: AudioFile
    public let episodeName: String
    public let episodeDate: Date?

    public init(audioFile: AudioFile, episodeName: String, episodeDate: Date?) {
        self.audioFile = audioFile
        self.episodeName = episodeName
        self.episodeDate = episodeDate
    }
}

public struct EpisodeMetadata: Equatable {
    public let episodeName: String
    public let episodeDate: Date?

    public init(episodeName: String, episodeDate: Date?) {
        self.episodeName = episodeName
        self.episodeDate = episodeDate
    }
}
