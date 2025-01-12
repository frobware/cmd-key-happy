// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "cmd-key-happy",
  platforms: [
    .macOS(.v11)
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
  ],
  targets: [
    .executableTarget(
      name: "cmd-key-happy",
      dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]
    ),
  ]
)
