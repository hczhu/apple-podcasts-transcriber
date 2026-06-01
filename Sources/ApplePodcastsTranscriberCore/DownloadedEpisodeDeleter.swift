import Foundation

public struct DownloadedEpisodeDeletionFailure: Equatable {
    public let url: URL
    public let message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct DownloadedEpisodeDeletionResult: Equatable {
    public let deletedURLs: [URL]
    public let failures: [DownloadedEpisodeDeletionFailure]

    public init(deletedURLs: [URL], failures: [DownloadedEpisodeDeletionFailure]) {
        self.deletedURLs = deletedURLs
        self.failures = failures
    }
}

public struct DownloadedEpisodeDeleter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func delete(_ audioFiles: [AudioFile]) -> DownloadedEpisodeDeletionResult {
        var deletedURLs: [URL] = []
        var failures: [DownloadedEpisodeDeletionFailure] = []

        for audioFile in audioFiles {
            do {
                try fileManager.removeItem(at: audioFile.url)
                deletedURLs.append(audioFile.url)
            } catch {
                failures.append(DownloadedEpisodeDeletionFailure(
                    url: audioFile.url,
                    message: error.localizedDescription
                ))
            }
        }

        return DownloadedEpisodeDeletionResult(
            deletedURLs: deletedURLs,
            failures: failures
        )
    }
}
