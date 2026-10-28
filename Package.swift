// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "G90SDR",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "G90SDR", path: "Sources/G90SDR")
    ]
)
