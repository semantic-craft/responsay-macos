// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ResponsayCore",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "ResponsayCore", targets: ["ResponsayCore"]),
        // 354 — shared speech package: capture-service implementations + (later) the
        // on-device engine, reusable by both the macOS and iOS app targets.
        .library(name: "ResponsaySpeech", targets: ["ResponsaySpeech"]),
        .executable(name: "ResponsayMaintenance", targets: ["ResponsayMaintenance"])
    ],
    targets: [
        .target(
            name: "ResponsayCore",
            resources: [.copy("LegalBrain/LegalSkills")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "ResponsaySpeech",
            dependencies: ["ResponsayCore"]
        ),
        .executableTarget(
            name: "ResponsayMaintenance",
            dependencies: ["ResponsayCore"]
        ),
        .testTarget(name: "ResponsayCoreTests", dependencies: ["ResponsayCore"]),
        .testTarget(name: "ResponsaySpeechTests", dependencies: ["ResponsaySpeech"])
    ]
)
