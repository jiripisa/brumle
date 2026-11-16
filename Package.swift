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
        // The Audio Unit (build.sh turns it into Brumle.component).
        .library(name: "BrumleAU", type: .dynamic, targets: ["BrumleAU", "BrumleAUExports"]),
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
        // Apple's AudioUnitSDK (Apache-2.0), vendored: it is not a Swift package.
        .target(
            name: "AudioUnitSDK",
            path: "ThirdParty/AudioUnitSDK",
            exclude: ["LICENSE.txt"],
            sources: ["src"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreMIDI"),
            ]
        ),
        // The Audio Unit (AUv2 instrument). build.sh wraps the dylib into Brumle.component.
        .target(
            name: "BrumleAU",
            dependencies: ["BrumleDSP", "AudioUnitSDK"],
            path: "Sources/BrumleAU"
        ),
        // No code, only what the Audio Unit's dynamic library exports.
        .target(
            name: "BrumleAUExports",
            path: "Sources/BrumleAUExports",
            linkerSettings: [
                // A plug-in shares the host's process with other plug-ins: export only the
                // factory function the host looks up (AudioUnit-Info.plist, factoryFunction).
                .unsafeFlags(["-Xlinker", "-exported_symbol", "-Xlinker", "_BrumleAUFactory"]),
            ]
        ),
        .target(
            name: "BrumleCore",
            dependencies: ["BrumleDSP"],
            path: "Sources/BrumleCore"
        ),
        // The instrument's panel, the same in the app's window and in the plug-in's.
        .target(
            name: "BrumleUI",
            dependencies: ["BrumleCore"],
            path: "Sources/BrumleUI"
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
            // The Audio Unit too, which the tests run inside their own process, and the
            // panel's logic that does not need a window.
            dependencies: ["BrumleCore", "BrumleDSP", "BrumleReference", "BrumleAU", "BrumleUI"],
            path: "Tests/BrumleCoreTests"
        ),
    ],
    // AudioUnitSDK needs C++23.
    cxxLanguageStandard: .cxx2b
)
