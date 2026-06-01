import Foundation

public protocol Transcribing {
    func transcribe(episode: PodcastEpisode, language: String?) throws -> String
}

public enum TranscriptionBackend: String {
    case local
    case openai
}

public enum TranscriptionError: LocalizedError, Equatable {
    case missingLocalBinary(String)
    case missingLocalModel(String)
    case missingAPIKey(String)
    case invalidAPIResponse
    case processFailed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .missingLocalBinary(let path):
            return "Local whisper binary not found at \(path)."
        case .missingLocalModel(let path):
            return "Local speech-to-text model not found at \(path)."
        case .missingAPIKey(let name):
            return "Missing API key in \(name)."
        case .invalidAPIResponse:
            return "The transcription API returned an invalid response."
        case .processFailed(let status, let output):
            return "Local transcription failed with exit code \(status): \(output)"
        }
    }
}

public struct LocalWhisperTranscriber: Transcribing {
    private let binaryURL: URL
    private let modelURL: URL
    private let fileManager: FileManager

    public init(
        binaryURL: URL? = nil,
        modelURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.binaryURL = binaryURL ?? AppDefaults.resolvedLocalWhisperBinaryURL(fileManager: fileManager)
        self.modelURL = modelURL ?? AppDefaults.localModelURL
    }

    public func transcribe(episode: PodcastEpisode, language: String?) throws -> String {
        guard fileManager.fileExists(atPath: binaryURL.path) else {
            throw TranscriptionError.missingLocalBinary(binaryURL.path)
        }
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.missingLocalModel(modelURL.path)
        }

        let outputPrefix = fileManager.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString)")

        let process = Process()
        process.executableURL = binaryURL
        var arguments = [
            "-m", modelURL.path,
            "-f", episode.audioFile.url.path,
            "-otxt",
            "-of", outputPrefix.path,
            "-pp"
        ]

        if let language, !language.isEmpty {
            arguments.append(contentsOf: ["-l", language])
        }

        process.arguments = arguments
        // Let stderr stream directly to the terminal so progress is visible in real-time.
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(
                status: process.terminationStatus,
                output: ""
            )
        }

        let transcriptURL = outputPrefix.appendingPathExtension("txt")
        return try String(contentsOf: transcriptURL, encoding: .utf8)
    }
}

public struct LocalBackendStatus {
    public let binaryURL: URL
    public let modelURL: URL
    public let binaryExists: Bool
    public let modelExists: Bool

    public var isReady: Bool {
        binaryExists && modelExists
    }
}

public struct LocalBackendChecker {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func status() -> LocalBackendStatus {
        let binaryURL = AppDefaults.resolvedLocalWhisperBinaryURL(fileManager: fileManager)
        let modelURL = AppDefaults.localModelURL

        return LocalBackendStatus(
            binaryURL: binaryURL,
            modelURL: modelURL,
            binaryExists: fileManager.fileExists(atPath: binaryURL.path),
            modelExists: fileManager.fileExists(atPath: modelURL.path)
        )
    }
}

public struct OpenAICompatibleTranscriber: Transcribing {
    private let apiKey: String?
    private let baseURL: URL
    private let model: String
    private let urlSession: URLSession

    public init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = ProcessInfo.processInfo.environment["OPENAI_TRANSCRIPTION_MODEL"] ?? "whisper-1",
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.urlSession = urlSession
    }

    public func transcribe(episode: PodcastEpisode, language: String?) throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey("OPENAI_API_KEY")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(
            boundary: boundary,
            audioURL: episode.audioFile.url,
            model: model,
            language: language
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?

        urlSession.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }

            if let error {
                result = .failure(error)
                return
            }

            result = .success(data ?? Data())
        }.resume()

        semaphore.wait()

        let data = try result?.get() ?? Data()
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = response?["text"] as? String else {
            throw TranscriptionError.invalidAPIResponse
        }

        return text
    }

    private func multipartBody(
        boundary: String,
        audioURL: URL,
        model: String,
        language: String?
    ) throws -> Data {
        var body = Data()

        body.appendFormField(name: "model", value: model, boundary: boundary)
        if let language, !language.isEmpty {
            body.appendFormField(name: "language", value: language, boundary: boundary)
        }
        body.appendFileField(
            name: "file",
            filename: audioURL.lastPathComponent,
            contentType: contentType(for: audioURL),
            data: try Data(contentsOf: audioURL),
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")

        return body
    }

    private func contentType(for audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "aac":
            return "audio/aac"
        default:
            return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
