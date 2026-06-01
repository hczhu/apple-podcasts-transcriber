import Foundation

public struct TranscriptStore {
    public let outputDirectory: URL

    private let fileManager: FileManager

    public init(
        outputDirectory: URL = AppDefaults.transcriptOutputDirectory,
        fileManager: FileManager = .default
    ) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
    }

    public func transcriptURL(for episodeName: String, date: Date?) -> URL {
        outputDirectory.appendingPathComponent(Self.safeFilename(for: episodeName, date: date))
    }

    public func transcriptExists(for episodeName: String, date: Date?) -> Bool {
        fileManager.fileExists(atPath: transcriptURL(for: episodeName, date: date).path)
    }

    @discardableResult
    public func write(_ text: String, for episodeName: String, date: Date?) throws -> URL {
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let outputURL = transcriptURL(for: episodeName, date: date)
        try text.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    public static func safeFilename(for episodeName: String, date: Date?) -> String {
        var name = episodeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if name.isEmpty {
            name = "Untitled Episode"
        }

        let invalidScalars = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.controlCharacters)

        let sanitizedScalars = name.unicodeScalars.map { scalar -> Character in
            invalidScalars.contains(scalar) ? "-" : Character(scalar)
        }

        let sanitized = String(sanitizedScalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        let title = sanitized.isEmpty ? "Untitled Episode" : sanitized

        if let date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return "\(formatter.string(from: date)) - \(title).txt"
        }
        return "\(title).txt"
    }
}
