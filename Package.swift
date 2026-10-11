// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "SafePaste",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "SafePaste",
      path: "Sources/SafePaste",
      linkerSettings: [
        .linkedLibrary("sqlite3")
      ]
    )
  ]
)
