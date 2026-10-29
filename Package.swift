// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WritingAssistant",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "WritingAssistantCore",
            resources: [.copy("Resources/Prompts")]
        ),
        .executableTarget(
            name: "WritingAssistant",
            dependencies: ["WritingAssistantCore"]
        ),
        .testTarget(
            name: "WritingAssistantCoreTests",
            dependencies: ["WritingAssistantCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "WritingAssistantTests",
            dependencies: ["WritingAssistant", "WritingAssistantCore"]
        ),
    ]
)
