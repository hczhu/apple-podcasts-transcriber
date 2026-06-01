import Foundation

public final class PodcastLibraryScanner {
    private let fileManager: FileManager
    private let supportedExtensions: Set<String>

    public init(
        fileManager: FileManager = .default,
        supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "mp4"]
    ) {
        self.fileManager = fileManager
        self.supportedExtensions = supportedExtensions
    }

    public func scan(_ root: URL = AppDefaults.podcastLibraryRoot) throws -> [AudioFile] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PodcastLibraryScannerError.unreadableDirectory(root.path)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw PodcastLibraryScannerError.unreadableDirectory(root.path)
        }

        var files: [AudioFile] = []

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey
            ])
            guard values.isRegularFile == true else { continue }

            let pathExtension = url.pathExtension.lowercased()
            guard supportedExtensions.contains(pathExtension) else { continue }

            files.append(AudioFile(
                url: url,
                byteSize: UInt64(values.fileSize ?? 0),
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate
            ))
        }

        return files.sorted { lhs, rhs in
            lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }
}

public enum PodcastLibraryScannerError: LocalizedError, Equatable {
    case unreadableDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableDirectory(let path):
            return "Could not read podcast library at \(path)."
        }
    }
}
