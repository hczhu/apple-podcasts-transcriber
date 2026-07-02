import ApplePodcastsTranscriberCore
import Darwin
import Foundation

signal(SIGINT) { _ in
    let pid = activeTranscriptionPID
    if pid != 0 { kill(pid, SIGTERM) }
    signal(SIGINT, SIG_DFL)
    raise(SIGINT)
}
signal(SIGTERM) { _ in
    let pid = activeTranscriptionPID
    if pid != 0 { kill(pid, SIGTERM) }
    exit(143)
}

enum CLIError: LocalizedError {
    case missingValue(String)
    case invalidBackend(String)
    case invalidLimit(String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidBackend(let value):
            return "Invalid backend: \(value). Use local or openai."
        case .invalidLimit(let value):
            return "Invalid limit: \(value)."
        case .unknownOption(let option):
            return "Unknown option: \(option)."
        }
    }
}

struct CLIOptionsParser {
    func parse(_ arguments: [String]) throws -> PodcastTranscriptionOptions? {
        var backend = TranscriptionBackend.local
        var libraryURL = AppDefaults.podcastLibraryRoot
        var outputDirectory = AppDefaults.transcriptOutputDirectory
        var force = false
        var limit: Int?
        var episodeFilter: String?
        var language: String?
        var listOnly = false
        var deleteDownloadedEpisodes = false
        var deleteAfterTranscription = true

        var index = 0
        while index < arguments.count {
            let option = arguments[index]

            switch option {
            case "--help", "-h":
                printUsage()
                return nil
            case "--check-local-backend":
                printLocalBackendStatus()
                return nil
            case "--backend":
                let value = try value(after: option, in: arguments, at: &index)
                guard let parsedBackend = TranscriptionBackend(rawValue: value) else {
                    throw CLIError.invalidBackend(value)
                }
                backend = parsedBackend
            case "--library":
                libraryURL = URL(fileURLWithPath: try value(after: option, in: arguments, at: &index))
            case "--output":
                outputDirectory = URL(fileURLWithPath: try value(after: option, in: arguments, at: &index))
            case "--force":
                force = true
            case "--limit":
                let rawLimit = try value(after: option, in: arguments, at: &index)
                guard let parsedLimit = Int(rawLimit), parsedLimit >= 0 else {
                    throw CLIError.invalidLimit(rawLimit)
                }
                limit = parsedLimit
            case "--episode":
                episodeFilter = try value(after: option, in: arguments, at: &index)
            case "--language":
                language = try value(after: option, in: arguments, at: &index)
            case "--list":
                listOnly = true
            case "--delete-downloaded-episodes":
                deleteDownloadedEpisodes = true
            case "--no-delete-after-transcription":
                deleteAfterTranscription = false
            default:
                throw CLIError.unknownOption(option)
            }

            index += 1
        }

        return PodcastTranscriptionOptions(
            backend: backend,
            libraryURL: libraryURL,
            outputDirectory: outputDirectory,
            force: force,
            limit: limit,
            episodeFilter: episodeFilter,
            language: language,
            listOnly: listOnly,
            deleteDownloadedEpisodes: deleteDownloadedEpisodes,
            deleteAfterTranscription: deleteAfterTranscription
        )
    }

    private func value(after option: String, in arguments: [String], at index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError.missingValue(option)
        }

        index = valueIndex
        return arguments[valueIndex]
    }

    private func printUsage() {
        print("""
        Usage:
          apple-podcasts-transcriber [options]

        Options:
          --backend local|openai   Transcription backend. Default: local
          --force                  Overwrite existing transcript files. Default: false
          --limit N                Process only the first N newest episodes. Default: no limit
          --episode TEXT           Process episodes whose name contains TEXT. Default: all episodes
          --language CODE          Input language code, such as en, zh, ja. Default: auto-detect
          --list                   List episodes without transcribing. Default: false
          --delete-downloaded-episodes
                                   Delete all discovered downloaded episode audio files. Default: false
          --no-delete-after-transcription
                                   Keep episode audio files after transcription. Default: delete after transcription
          --check-local-backend    Check local whisper.cpp binary/model setup. Default: false
          --library PATH           Apple Podcasts library path. Default: \(AppDefaults.podcastLibraryRoot.path)
          --output PATH            Transcript output directory. Default: \(AppDefaults.transcriptOutputDirectory.path)
          --help                   Show this help
        """)
    }

    private func printLocalBackendStatus() {
        let status = LocalBackendChecker().status()

        print("""
        Local backend setup:
          whisper-cli: \(status.binaryExists ? "found" : "missing") at \(status.binaryURL.path)
          model:       \(status.modelExists ? "found" : "missing") at \(status.modelURL.path)

        Environment overrides:
          APPLE_PODCASTS_TRANSCRIBER_WHISPER_CLI=/path/to/whisper-cli
          APPLE_PODCASTS_TRANSCRIBER_MODEL=/path/to/ggml-base.bin
        """)

        if !status.isReady {
            print("""

            Local backend is not ready.

            Expected setup:
              1. Install whisper.cpp so `whisper-cli` exists.
              2. Download a multilingual GGML model file, such as ggml-base.bin.
              3. Put the model at the path above, or set APPLE_PODCASTS_TRANSCRIBER_MODEL.
            """)
        }
    }
}

do {
    if let options = try CLIOptionsParser().parse(Array(CommandLine.arguments.dropFirst())) {
        try PodcastTranscriptionApp().run(options: options)
    }
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}
