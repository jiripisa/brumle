// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Brumle",
    platforms: [
        .macOS(.v26)
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
        // The sound engine: C++ with a C interface (include/BrumleDSP.h).
        .target(
            name: "BrumleDSP",
            path: "Sources/BrumleDSP"
        ),
        .target(
            name: "BrumleCore",
            dependencies: ["BrumleDSP"],
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
        // The throwaway prototype (.planning/research/spike) as a C++ reference the
        // engine is compared against in tests. Test-only: never linked into the app.
        .target(name: "BrumleReference", path: "Tests/BrumleReference"),
        .testTarget(
            name: "BrumleCoreTests",
            dependencies: ["BrumleCore", "BrumleDSP", "BrumleReference"],
            path: "Tests/BrumleCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx2b
)
