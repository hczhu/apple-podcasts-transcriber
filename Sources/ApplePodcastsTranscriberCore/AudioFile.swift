import Foundation

public struct AudioFile: Equatable {
    public let url: URL
    public let byteSize: UInt64
    public let creationDate: Date?
    public let modificationDate: Date?

    public init(
        url: URL,
        byteSize: UInt64,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.url = url
        self.byteSize = byteSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    public var fallbackEpisodeName: String {
        url.deletingPathExtension().lastPathComponent
    }

    public var fallbackEpisodeDate: Date? {
        creationDate ?? modificationDate
    }
}
