// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NoteLight",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "NoteLight",
            targets: ["YazbozNoteApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "YazbozNoteApp",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "YazbozNoteAppTests",
            dependencies: ["YazbozNoteApp"]
        )
    ]
)
