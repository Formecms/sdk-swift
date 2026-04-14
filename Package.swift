// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Forme",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "Forme",
            targets: ["Forme"]
        ),
    ],
    dependencies: [
        // Zero production dependencies — URLSession only.
        // Test-only dependency: swift-testing (Apple's new Swift Testing framework)
        // lets us run tests cross-platform without requiring Xcode/XCTest.
        .package(url: "https://github.com/swiftlang/swift-testing", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "Forme",
            path: "Sources/Forme"
        ),
        .testTarget(
            name: "FormeTests",
            dependencies: [
                "Forme",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/FormeTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
