// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MedASRBar",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "MedASRBar",
            path: "Sources/MedASRBar")
    ]
)
