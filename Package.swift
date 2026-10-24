// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotStyle",
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
    ],
    targets: [
        .target(
            name: "ShotStyleCore",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ShotStyleCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ShotStyle",
            dependencies: [
                "ShotStyleCore",
            ],
            path: "Sources/ShotStyle"
        ),
        .testTarget(
            name: "ShotStyleCoreTests",
            dependencies: [
                "ShotStyleCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Tests/ShotStyleCoreTests"
        ),
        // Swift Testing (runs with `swift test` next to the XCTest suite).
        .testTarget(
            name: "ShotStyleTextPlacementTests",
            dependencies: ["ShotStyleCore"],
            path: "Tests/ShotStyleTextPlacementTests"
        ),
    ]
)
