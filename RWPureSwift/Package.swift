// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RWPureSwift",
    platforms: [.iOS(.v17), .macCatalyst(.v17)],
    products: [
        .library(name: "AppModel", targets: ["AppModel"]),
        .library(name: "AppNavigation", targets: ["AppNavigation"]),
        .library(name: "CheckPermissions", targets: ["CheckPermissions"]),
        .library(name: "Dashboard", targets: ["Dashboard"]),
        .library(name: "DataModel", targets: ["DataModel"]),
        .library(name: "EditSettings", targets: ["EditSettings"]),
        .library(name: "Slideshow", targets: ["Slideshow"]),
        .library(name: "Utility", targets: ["Utility"]),
    ],
    dependencies: [
        .package(url: "https://github.com/chotchki/LibNFCSwift.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "AppModel", swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "AppNavigation", dependencies: [
            .target(name: "AppModel"),
            .target(name: "CheckPermissions"),
            .target(name: "Dashboard"),
            .target(name: "EditSettings")
        ], swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "CheckPermissions", dependencies: [
            .target(name: "AppModel"),
            .target(name: "DataModel"),
            .target(name: "Utility")
        ], swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "Dashboard", dependencies: [
            .target(name: "DataModel"),
            .target(name: "Slideshow"),
            .target(name: "Utility"),
            .target(name: "TagScan", condition: .when(platforms: [.macCatalyst]))
        ], swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "DataModel", swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .testTarget(name: "DataModelTests", dependencies: [.target(name: "DataModel")]),
        .target(name: "EditSettings",
                dependencies: [
                    .target(name: "AppModel"),
                    .target(name: "DataModel"),
                    .target(name: "TagScan"),
                    .target(name: "Utility"),
                ], swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "Slideshow",
                dependencies: [
                    .target(name: "AppModel"),
                    .target(name: "DataModel"),
                    .target(name: "Utility"),
                ], 
                resources:[ .process("Widget/Resources/PreviewAssets.xcassets")],
                swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "TagScan",
                dependencies: [
                    .product(name: "LibNFCSwift", package: "LibNFCSwift", condition: .when(platforms: [.macCatalyst])),
                    .target(name: "DataModel"),
                    .target(name: "Utility"),
                ], swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
        .target(name: "Utility", swiftSettings: [ .enableExperimentalFeature("StrictConcurrency")]),
    ]
)
