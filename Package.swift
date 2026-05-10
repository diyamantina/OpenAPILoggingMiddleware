// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenAPILoggingMiddleware",
    // Supported platforms (CI verifies all of them):
    //   - macOS 13+    (full swift build + test)
    //   - iOS 16+      (xcodebuild build verification)
    //   - tvOS 16+     (xcodebuild build verification)
    //   - watchOS 9+   (xcodebuild build verification)
    //   - Linux        (Swift 6.0 container, full swift build + test)
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "OpenAPILoggingMiddleware",
            targets: ["OpenAPILoggingMiddleware"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3")
    ],
    targets: [
        .target(
            name: "OpenAPILoggingMiddleware",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "OpenAPILoggingMiddlewareTests",
            dependencies: [
                "OpenAPILoggingMiddleware",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
