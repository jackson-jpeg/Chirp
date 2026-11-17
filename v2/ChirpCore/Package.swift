// swift-tools-version: 6.0
//
// ChirpCore: the clean core of ChirpChirps 2.0. Pure logic only (Foundation and
// CryptoKit): identity, wire format, router, floor control, jitter buffer,
// channels, blocking, location consent, demo gate, roster, texts.
//
// No AVFoundation, no MultipeerConnectivity, no UIKit here. The app target owns
// those and drives this package, so everything that decides anything is tested
// with `swift test` on a Mac, with no simulator and no radio.
import PackageDescription

let package = Package(
    name: "ChirpCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "ChirpCore", targets: ["ChirpCore"]),
    ],
    targets: [
        .target(
            name: "ChirpCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "ChirpCoreTests",
            dependencies: ["ChirpCore"]
        ),
    ]
)
