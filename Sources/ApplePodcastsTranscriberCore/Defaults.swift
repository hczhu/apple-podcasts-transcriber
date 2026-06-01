import Foundation

public enum AppDefaults {
    public static let podcastLibraryRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/243LU875E5.groups.com.apple.podcasts")

    public static let transcriptOutputDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Apple Podcast Transcripts")

    public static let localModelDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/apple-podcasts-transcriber/models")

    public static let defaultLocalModelURL = localModelDirectory
        .appendingPathComponent("ggml-base.bin")

    public static let defaultLocalWhisperBinaryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/apple-podcasts-transcriber/whisper.cpp/whisper-cli")

    public static let localModelURL = ProcessInfo.processInfo.environment["APPLE_PODCASTS_TRANSCRIBER_MODEL"]
        .map(URL.init(fileURLWithPath:)) ?? defaultLocalModelURL

    public static func resolvedLocalWhisperBinaryURL(fileManager: FileManager = .default) -> URL {
        for candidate in localWhisperBinaryCandidates {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return localWhisperBinaryCandidates[0]
    }

    public static var localWhisperBinaryCandidates: [URL] {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["APPLE_PODCASTS_TRANSCRIBER_WHISPER_CLI"] {
            candidates.append(URL(fileURLWithPath: override))
        }

        candidates.append(contentsOf: [
            defaultLocalWhisperBinaryURL,
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ])

        return candidates
    }
}
