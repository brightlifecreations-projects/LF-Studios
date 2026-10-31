// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LFStudios",
    // English strings are the keys; translations live in
    // Localization/Localizable.xcstrings (see scripts/localize.py).
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Vendored (MIT, from sindresorhus/KeyboardShortcuts 2.4.x) with one
        // patch: its `Bundle.module`-based localization crashed released .app
        // bundles on machines other than the build machine (issue #25) — the
        // vendored copy locates its resource bundle in Contents/Resources.
        .package(path: "Vendor/KeyboardShortcuts"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
        // Whisper captions, on the Mac with Core ML (MIT). Pinned: model
        // downloads and loading are driven by LF Studios, never by itself.
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.1.1"),
    ],
    targets: [
        .target(
            name: "LFStudiosCore",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/LFStudiosCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LFStudios",
            dependencies: [
                "LFStudiosCore",
            ],
            path: "Sources/LFStudios"
        ),
        .testTarget(
            name: "LFStudiosCoreTests",
            dependencies: [
                "LFStudiosCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Tests/LFStudiosCoreTests",
            // 1.13.0's frames, read by path (OldProjectPixelTests).
            exclude: ["Fixtures"]
        ),
        // Swift Testing (runs with `swift test` next to the XCTest suite).
        .testTarget(
            name: "LFStudiosTextPlacementTests",
            dependencies: ["LFStudiosCore"],
            path: "Tests/LFStudiosTextPlacementTests"
        ),
    ]
)
