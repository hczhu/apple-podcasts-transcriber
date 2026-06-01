import AVFoundation
import Foundation

public protocol EpisodeMetadataReading {
    func readMetadata(from audioFile: AudioFile) throws -> EpisodeMetadata
}

public protocol AudioMetadataReading {
    func readMetadata(at url: URL) throws -> AudioMetadata
}

public protocol SpotlightMetadataReading {
    func readMetadata(at url: URL) throws -> SpotlightMetadata
}

public struct AudioMetadata: Equatable {
    public let title: String?
    public let creationDate: Date?

    public init(title: String?, creationDate: Date?) {
        self.title = title
        self.creationDate = creationDate
    }
}

public struct SpotlightMetadata: Equatable {
    public let title: String?
    public let contentCreationDate: Date?

    public init(title: String?, contentCreationDate: Date?) {
        self.title = title
        self.contentCreationDate = contentCreationDate
    }
}

public struct FileEpisodeMetadataReader: EpisodeMetadataReading {
    private let audioMetadataReader: AudioMetadataReading
    private let spotlightMetadataReader: SpotlightMetadataReading

    public init(
        audioMetadataReader: AudioMetadataReading = AVFoundationAudioMetadataReader(),
        spotlightMetadataReader: SpotlightMetadataReading = SpotlightMetadataReader()
    ) {
        self.audioMetadataReader = audioMetadataReader
        self.spotlightMetadataReader = spotlightMetadataReader
    }

    public func readMetadata(from audioFile: AudioFile) throws -> EpisodeMetadata {
        let audioMetadata = try? audioMetadataReader.readMetadata(at: audioFile.url)
        let spotlightMetadata = try? spotlightMetadataReader.readMetadata(at: audioFile.url)

        return EpisodeMetadata(
            episodeName: normalizedEpisodeName(
                audioMetadata?.title
                    ?? spotlightMetadata?.title
                    ?? audioFile.fallbackEpisodeName
            ),
            episodeDate: audioMetadata?.creationDate
                ?? spotlightMetadata?.contentCreationDate
                ?? audioFile.fallbackEpisodeDate
        )
    }

    private func normalizedEpisodeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Episode" : trimmed
    }
}

public struct AVFoundationAudioMetadataReader: AudioMetadataReading {
    public init() {}

    public func readMetadata(at url: URL) throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        let metadata = try Self.loadCommonMetadata(from: asset)
        let title = Self.stringValue(
            from: metadata,
            identifier: .commonIdentifierTitle
        )
        let creationDate = Self.dateValue(
            from: metadata,
            identifier: .commonIdentifierCreationDate
        )

        return AudioMetadata(title: title, creationDate: creationDate)
    }

    private static func loadCommonMetadata(from asset: AVURLAsset) throws -> [AVMetadataItem] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[AVMetadataItem], Error>?

        Task {
            do {
                result = .success(try await asset.load(.commonMetadata))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try result?.get() ?? []
    }

    private static func stringValue(
        from metadataItems: [AVMetadataItem],
        identifier: AVMetadataIdentifier
    ) -> String? {
        guard let item = AVMetadataItem
            .metadataItems(from: metadataItems, filteredByIdentifier: identifier)
            .first else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        Task {
            result = try? await item.load(.stringValue)
            semaphore.signal()
        }

        semaphore.wait()

        let value = result?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func dateValue(
        from metadataItems: [AVMetadataItem],
        identifier: AVMetadataIdentifier
    ) -> Date? {
        guard let rawValue = stringValue(from: metadataItems, identifier: identifier) else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: rawValue) {
            return date
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return fallbackFormatter.date(from: rawValue)
    }
}

public struct SpotlightMetadataReader: SpotlightMetadataReading {
    private let mdlsURL: URL

    public init(mdlsURL: URL = URL(fileURLWithPath: "/usr/bin/mdls")) {
        self.mdlsURL = mdlsURL
    }

    public func readMetadata(at url: URL) throws -> SpotlightMetadata {
        let process = Process()
        process.executableURL = mdlsURL
        process.arguments = [
            "-raw",
            "-name", "kMDItemTitle",
            "-name", "kMDItemContentCreationDate",
            url.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return SpotlightMetadata(title: nil, contentCreationDate: nil)
        }

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        return SpotlightMetadata(
            title: metadataValue(at: 0, in: lines),
            contentCreationDate: metadataDate(at: 1, in: lines)
        )
    }

    private func metadataValue(at index: Int, in lines: [String]) -> String? {
        guard index < lines.count else {
            return nil
        }

        let value = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "(null)" else {
            return nil
        }

        return value
    }

    private func metadataDate(at index: Int, in lines: [String]) -> Date? {
        guard let rawValue = metadataValue(at: index, in: lines) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: rawValue)
    }
}
