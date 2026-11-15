// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brumle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The macOS app (bundle assembled by build.sh — see development_workflow.md §2).
        .executable(name: "Brumle", targets: ["Brumle"]),
        // App logic without UI — what `swift test` covers.
        .library(name: "BrumleCore", targets: ["BrumleCore"]),
    ],
    dependencies: [
        // Auto-update: the standard updater for apps outside the App Store;
        // EdDSA-signed appcast on GitHub Pages.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .target(
            name: "BrumleCore",
            path: "Sources/BrumleCore"
        ),
        .executableTarget(
            name: "Brumle",
            dependencies: [
                "BrumleCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Brumle",
            linkerSettings: [
                // Embedded frameworks ship in Contents/Frameworks (build.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "BrumleCoreTests",
            dependencies: ["BrumleCore"],
            path: "Tests/BrumleCoreTests"
        ),
    ]
)
