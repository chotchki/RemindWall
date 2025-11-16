// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RWPureSwift",
    platforms: [.iOS(.v18), .macCatalyst(.v18)],
    products: [
        .library(name: "AppModel", targets: ["AppModel"]),
        .library(name: "AppNavigation", targets: ["AppNavigation"]),
        .library(name: "CheckPermissions", targets: ["CheckPermissions"]),
        .library(name: "Dashboard", targets: ["Dashboard"]),
        .library(name: "DataModel", targets: ["DataModel"]),
        .library(name: "EditSettings", targets: ["EditSettings"]),
        .library(name: "PhotoKitAsync", targets: ["PhotoKitAsync"]),
        .library(name: "Slideshow", targets: ["Slideshow"]),
        .library(name: "TagScan", targets: ["TagScan"]),
        .library(name: "Utility", targets: ["Utility"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
        .package(
              url: "https://github.com/pointfreeco/swift-composable-architecture",
              from: "1.22.0"
            ),
        .package(url: "https://github.com/ph1ps/swift-concurrency-deadline.git", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.6.0")
    ],
    targets: [
        .target(name: "AppModel"),
        .target(name: "AppNavigation", dependencies: [
            .target(name: "AppModel"),
            .target(name: "CheckPermissions"),
            .target(name: "Dashboard"),
            .target(name: "EditSettings")
        ]),
        .target(name: "CheckPermissions", dependencies: [
            .target(name: "AppModel"),
            .target(name: "DataModel"),
            .target(name: "Utility")
        ]),
        .target(name: "Dashboard", dependencies: [
            .target(name: "DataModel"),
            .target(name: "Slideshow"),
            .target(name: "Utility"),
            .target(name: "TagScan")
        ]),
        .target(name: "PhotoKitAsync", dependencies: [
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
            .product(name:"Tagged", package: "swift-tagged")
        ]),
        .testTarget(name: "PhotoKitAsyncTests", dependencies: ["PhotoKitAsync"]),
        .target(name: "EditSettings",
                dependencies: [
                    .target(name: "AppModel"),
                    .target(name: "DataModel"),
                    .target(name: "PhotoKitAsync"),
                    .target(name: "TagScan"),
                    .target(name: "Utility"),
                ]),
        .target(name: "DataModel"),
        .target(name: "Slideshow",
                dependencies: [
                    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                    .target(name: "AppModel"),
                    .target(name: "DataModel"),
                    .target(name: "PhotoKitAsync"),
                    .target(name: "Utility"),
                ], 
                resources:[ .process("Widget/Resources/PreviewAssets.xcassets")]),
        .target(name: "TagScan",
                dependencies: [
                    .target(name: "DataModel"),
                    .target(name: "Utility"),
                    .product(name: "Deadline", package: "swift-concurrency-deadline")
                ]),
        .target(name: "Utility"),
    ]
)
