import Darwin
import Foundation

/// PID of the whisper-cli subprocess currently running; 0 when idle.
/// Read by signal handlers in the CLI target to kill the child on early exit.
public var activeTranscriptionPID: pid_t = 0

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
    case missingFFmpegBinary(String)
    case missingAPIKey(String)
    case invalidAPIResponse
    case processFailed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .missingLocalBinary(let path):
            return "Local whisper binary not found at \(path)."
        case .missingLocalModel(let path):
            return "Local speech-to-text model not found at \(path)."
        case .missingFFmpegBinary(let path):
            return "ffmpeg not found at \(path). Install it with: brew install ffmpeg"
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
    private let ffmpegURL: URL
    private let fileManager: FileManager

    public init(
        binaryURL: URL? = nil,
        modelURL: URL? = nil,
        ffmpegURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.binaryURL = binaryURL ?? AppDefaults.resolvedLocalWhisperBinaryURL(fileManager: fileManager)
        self.modelURL = modelURL ?? AppDefaults.localModelURL
        self.ffmpegURL = ffmpegURL ?? AppDefaults.resolvedFFmpegURL(fileManager: fileManager)
    }

    public func transcribe(episode: PodcastEpisode, language: String?) throws -> String {
        guard fileManager.fileExists(atPath: binaryURL.path) else {
            throw TranscriptionError.missingLocalBinary(binaryURL.path)
        }
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.missingLocalModel(modelURL.path)
        }
        guard fileManager.fileExists(atPath: ffmpegURL.path) else {
            throw TranscriptionError.missingFFmpegBinary(ffmpegURL.path)
        }

        print("  Converting audio...")
        let wavURL = fileManager.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString).wav")
        defer { try? fileManager.removeItem(at: wavURL) }
        try convertToWAV(inputURL: episode.audioFile.url, outputURL: wavURL)

        print("  Loading model and running speech recognition...")
        let outputPrefix = fileManager.temporaryDirectory
            .appendingPathComponent("apple-podcasts-transcriber-\(UUID().uuidString)")

        let process = Process()
        process.executableURL = binaryURL
        var arguments = [
            "-m", modelURL.path,
            "-f", wavURL.path,
            "-otxt",
            "-of", outputPrefix.path,
            "-pp"
        ]

        if let language, !language.isEmpty {
            arguments.append(contentsOf: ["-l", language])
        }

        process.arguments = arguments

        // Stream per-segment stdout directly to the terminal.
        process.standardOutput = FileHandle.standardOutput

        // Capture stderr; forward only progress percentage lines to avoid model-loading noise.
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stderrDone = DispatchSemaphore(value: 0)
        let readFD = stderrPipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global(qos: .utility).async {
            defer {
                stderrDone.signal()
            }
            // Use POSIX read() which blocks until data is available, unlike availableData.
            var rawBuf = [UInt8](repeating: 0, count: 4096)
            var line = [UInt8]()
            while true {
                let n = Darwin.read(readFD, &rawBuf, rawBuf.count)
                if n <= 0 { break }
                for byte in rawBuf[..<n] {
                    // Whisper terminates progress lines with \r; treat both \r and \n as line endings.
                    if byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\n") {
                        if let text = String(bytes: line, encoding: .utf8), !text.isEmpty,
                           text.contains("progress ="),
                           let match = text.range(of: #"\d+%"#, options: .regularExpression) {
                            fputs("Progress: \(String(text[match]))\n", stderr)
                            fflush(stderr)
                        }
                        line.removeAll(keepingCapacity: true)
                    } else {
                        line.append(byte)
                    }
                }
            }
        }

        try process.run()
        activeTranscriptionPID = process.processIdentifier
        defer { activeTranscriptionPID = 0 }
        process.waitUntilExit()
        stderrDone.wait()

        let transcriptURL = outputPrefix.appendingPathExtension("txt")

        if process.terminationStatus != 0, !fileManager.fileExists(atPath: transcriptURL.path) {
            throw TranscriptionError.processFailed(
                status: process.terminationStatus,
                output: ""
            )
        }

        let data = try Data(contentsOf: transcriptURL)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func convertToWAV(inputURL: URL, outputURL: URL) throws {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-nostdin",
            "-i", inputURL.path,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            "-y",
            outputURL.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TranscriptionError.processFailed(status: process.terminationStatus, output: "ffmpeg conversion failed")
        }
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
