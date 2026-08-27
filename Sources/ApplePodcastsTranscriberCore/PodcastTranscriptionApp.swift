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
    public let deleteAfterTranscription: Bool
    public let useShowNotesPrompt: Bool

    public init(
        backend: TranscriptionBackend = .local,
        libraryURL: URL = AppDefaults.podcastLibraryRoot,
        outputDirectory: URL = AppDefaults.transcriptOutputDirectory,
        force: Bool = false,
        limit: Int? = nil,
        episodeFilter: String? = nil,
        language: String? = nil,
        listOnly: Bool = false,
        deleteDownloadedEpisodes: Bool = false,
        deleteAfterTranscription: Bool = true,
        useShowNotesPrompt: Bool = true
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
        self.deleteAfterTranscription = deleteAfterTranscription
        self.useShowNotesPrompt = useShowNotesPrompt
    }
}

public struct PodcastTranscriptionApp {
    private let scanner: PodcastLibraryScanner
    private let metadataReader: EpisodeMetadataReading
    private let downloadedEpisodeDeleter: DownloadedEpisodeDeleter
    private let showNotesReader: ShowNotesReading
    private let makeTranscriber: (TranscriptionBackend) -> Transcribing
    private let output: (String) -> Void

    public init(
        scanner: PodcastLibraryScanner = PodcastLibraryScanner(),
        metadataReader: EpisodeMetadataReading = FileEpisodeMetadataReader(),
        downloadedEpisodeDeleter: DownloadedEpisodeDeleter = DownloadedEpisodeDeleter(),
        showNotesReader: ShowNotesReading = MTLibraryShowNotesReader(),
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
        self.showNotesReader = showNotesReader
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
                output("\(episode.formattedDate ?? "undated") | \(episode.episodeName) | \(episode.audioFile.url.path)")
            }
            return
        }

        let transcriptStore = TranscriptStore(outputDirectory: options.outputDirectory)
        let transcriber = makeTranscriber(options.backend)
        var transcribedCount = 0
        var skippedCount = duplicateCount
        var failedCount = 0
        var transcribedResults: [(title: String, path: String)] = []

        output("Found \(episodes.count) episode(s). Processing newest first.")
        if let language = options.language {
            output("Transcription language: \(language)")
        }

        for episode in episodes {
            let transcriptURL = transcriptStore.transcriptURL(for: episode.episodeName, date: episode.formattedDate)

            if transcriptStore.transcriptExists(for: episode.episodeName, date: episode.formattedDate), !options.force {
                skippedCount += 1
                output("Skipping existing transcript: \(episode.episodeName) -> \(transcriptURL.path)")
                continue
            }

            do {
                output("Transcribing: \(episode.episodeName)")
                let prompt = options.useShowNotesPrompt ? showNotesPrompt(for: episode, options: options) : nil
                let text = try transcriber.transcribe(
                    episode: episode,
                    language: options.language,
                    prompt: prompt
                )
                let writtenURL = try transcriptStore.write(text, for: episode.episodeName, date: episode.formattedDate)
                transcribedCount += 1
                transcribedResults.append((title: episode.episodeName, path: writtenURL.path))
                output("Wrote: \(writtenURL.path)")
                if options.deleteAfterTranscription {
                    let result = downloadedEpisodeDeleter.delete([episode.audioFile])
                    for url in result.deletedURLs { output("Deleted: \(url.path)") }
                    for failure in result.failures { output("Failed to delete: \(failure.url.path) - \(failure.message)") }
                }
            } catch {
                failedCount += 1
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                output("Failed: \(episode.episodeName) - \(message)")
            }
        }

        output("Done. Transcribed: \(transcribedCount). Skipped: \(skippedCount). Failed: \(failedCount).")

        if !transcribedResults.isEmpty {
            let titleWidth = transcribedResults.map(\.title.count).max()!
            let header = "Title".padding(toLength: titleWidth, withPad: " ", startingAt: 0)
            let separator = String(repeating: "-", count: titleWidth) + "  " + String(repeating: "-", count: 4)
            output("")
            output("\(header)  Path")
            output(separator)
            for result in transcribedResults {
                let paddedTitle = result.title.padding(toLength: titleWidth, withPad: " ", startingAt: 0)
                output("\(paddedTitle)  \(result.path)")
            }
        }
    }

    /// Builds a Whisper initial prompt from the episode's show notes so that guest
    /// names, company names, and jargon are spelled the way the feed spells them.
    private func showNotesPrompt(for episode: PodcastEpisode, options: PodcastTranscriptionOptions) -> String? {
        guard let notes = showNotesReader.showNotes(for: episode, libraryURL: options.libraryURL),
              let prompt = TranscriptionPromptBuilder.prompt(from: notes) else {
            output("  No show notes found; transcribing without a prompt.")
            return nil
        }

        output("  Show notes prompt (\(prompt.count) chars): \(preview(prompt))")
        return prompt
    }

    private func preview(_ text: String, limit: Int = 80) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "..."
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

}
