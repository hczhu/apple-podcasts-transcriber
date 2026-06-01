// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "apple-podcasts-transcriber",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "apple-podcasts-transcriber",
            targets: ["ApplePodcastsTranscriberCLI"]
        )
    ],
    targets: [
        .target(
            name: "ApplePodcastsTranscriberCore"
        ),
        .executableTarget(
            name: "ApplePodcastsTranscriberCLI",
            dependencies: ["ApplePodcastsTranscriberCore"]
        ),
        .testTarget(
            name: "ApplePodcastsTranscriberTests",
            dependencies: ["ApplePodcastsTranscriberCore"]
        )
    ]
)
