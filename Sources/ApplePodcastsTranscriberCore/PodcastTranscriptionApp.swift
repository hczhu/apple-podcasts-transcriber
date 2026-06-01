import Foundation

public struct PodcastTranscriptionOptions {
    public let backend: TranscriptionBackend
    public let libraryURL: URL
    public let outputDirectory: URL
    public let force: Bool
    public let limit: Int?
    public let episodeFilter: String?
    public let language: String?
    public let listOnly: Bool
    public let deleteDownloadedEpisodes: Bool

    public init(
        backend: TranscriptionBackend = .local,
        libraryURL: URL = AppDefaults.podcastLibraryRoot,
        outputDirectory: URL = AppDefaults.transcriptOutputDirectory,
        force: Bool = false,
        limit: Int? = nil,
        episodeFilter: String? = nil,
        language: String? = nil,
        listOnly: Bool = false,
        deleteDownloadedEpisodes: Bool = false
    ) {
        self.backend = backend
        self.libraryURL = libraryURL
        self.outputDirectory = outputDirectory
        self.force = force
        self.limit = limit
        self.episodeFilter = episodeFilter
        self.language = language
        self.listOnly = listOnly
        self.deleteDownloadedEpisodes = deleteDownloadedEpisodes
    }
}

public struct PodcastTranscriptionApp {
    private let scanner: PodcastLibraryScanner
    private let metadataReader: EpisodeMetadataReading
    private let downloadedEpisodeDeleter: DownloadedEpisodeDeleter
    private let makeTranscriber: (TranscriptionBackend) -> Transcribing
    private let output: (String) -> Void

    public init(
        scanner: PodcastLibraryScanner = PodcastLibraryScanner(),
        metadataReader: EpisodeMetadataReading = FileEpisodeMetadataReader(),
        downloadedEpisodeDeleter: DownloadedEpisodeDeleter = DownloadedEpisodeDeleter(),
        makeTranscriber: @escaping (TranscriptionBackend) -> Transcribing = { backend in
            switch backend {
            case .local:
                return LocalWhisperTranscriber()
            case .openai:
                return OpenAICompatibleTranscriber()
            }
        },
        output: @escaping (String) -> Void = { print($0) }
    ) {
        self.scanner = scanner
        self.metadataReader = metadataReader
        self.downloadedEpisodeDeleter = downloadedEpisodeDeleter
        self.makeTranscriber = makeTranscriber
        self.output = output
    }

    public func run(options: PodcastTranscriptionOptions) throws {
        output("Scanning podcast library: \(options.libraryURL.path)")
        let files = try scanner.scan(options.libraryURL)

        guard !files.isEmpty else {
            output("No podcast audio files found in \(options.libraryURL.path).")
            return
        }

        output("Found \(files.count) audio file(s). Reading episode metadata...")

        var episodes: [PodcastEpisode] = []
        episodes.reserveCapacity(files.count)

        for (index, audioFile) in files.enumerated() {
            let metadata = try metadataReader.readMetadata(from: audioFile)
            episodes.append(PodcastEpisode(
                audioFile: audioFile,
                episodeName: metadata.episodeName,
                episodeDate: metadata.episodeDate
            ))

            let completed = index + 1
            if completed == files.count || completed.isMultiple(of: 25) {
                output("Read metadata for \(completed)/\(files.count) audio file(s).")
            }
        }

        output("Sorting episodes newest first.")
        episodes = EpisodeSorter.newestFirst(episodes)

        if let episodeFilter = options.episodeFilter {
            episodes = episodes.filter {
                $0.episodeName.localizedCaseInsensitiveContains(episodeFilter)
            }
            output("Filtered to \(episodes.count) episode(s) matching \"\(episodeFilter)\".")
        }

        let episodeGroups = EpisodeDeduplicator.groupByDateAndTitle(episodes)
        let duplicateCount = episodeGroups.reduce(0) { $0 + $1.duplicateCount }

        if duplicateCount > 0 {
            output("Grouped \(episodes.count) audio file(s) into \(episodeGroups.count) unique episode(s) by date and title.")
        }

        if options.deleteDownloadedEpisodes {
            deleteDownloadedEpisodes(episodeGroups)
            return
        }

        episodes = episodeGroups.map(\.representativeEpisode)

        if let limit = options.limit {
            episodes = Array(episodes.prefix(limit))
            output("Limited to \(episodes.count) episode(s).")
        }

        guard !episodes.isEmpty else {
            output("No podcast episodes matched the requested options.")
            return
        }

        if options.listOnly {
            output("Date | Episode Title | Audio File")
            for episode in episodes {
                output("\(formatDate(episode.episodeDate)) | \(episode.episodeName) | \(episode.audioFile.url.path)")
            }
            return
        }

        let transcriptStore = TranscriptStore(outputDirectory: options.outputDirectory)
        let transcriber = makeTranscriber(options.backend)
        var transcribedCount = 0
        var skippedCount = duplicateCount
        var failedCount = 0

        output("Found \(episodes.count) episode(s). Processing newest first.")
        if let language = options.language {
            output("Transcription language: \(language)")
        }

        for episode in episodes {
            let transcriptURL = transcriptStore.transcriptURL(for: episode.episodeName, date: episode.episodeDate)

            if transcriptStore.transcriptExists(for: episode.episodeName, date: episode.episodeDate), !options.force {
                skippedCount += 1
                output("Skipping existing transcript: \(episode.episodeName) -> \(transcriptURL.path)")
                continue
            }

            do {
                output("Transcribing: \(episode.episodeName)")
                let text = try transcriber.transcribe(episode: episode, language: options.language)
                let writtenURL = try transcriptStore.write(text, for: episode.episodeName, date: episode.episodeDate)
                transcribedCount += 1
                output("Wrote: \(writtenURL.path)")
            } catch {
                failedCount += 1
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                output("Failed: \(episode.episodeName) - \(message)")
            }
        }

        output("Done. Transcribed: \(transcribedCount). Skipped: \(skippedCount). Failed: \(failedCount).")
    }

    private func deleteDownloadedEpisodes(_ groups: [PodcastEpisodeGroup]) {
        let files = groups.flatMap(\.allAudioFiles)
        output("Deleting \(files.count) downloaded episode file(s).")

        let result = downloadedEpisodeDeleter.delete(files)

        for url in result.deletedURLs {
            output("Deleted: \(url.path)")
        }

        for failure in result.failures {
            output("Failed to delete: \(failure.url.path) - \(failure.message)")
        }

        output("Done. Deleted: \(result.deletedURLs.count). Failed: \(result.failures.count).")
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else {
            return "undated"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
