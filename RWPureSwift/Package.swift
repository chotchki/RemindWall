// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RWPureSwift",
    platforms: [.iOS(.v17), .macCatalyst(.v17)],
    products: [
        .library(name: "AppNavigation", targets: ["AppNavigation"]),
        .library(name: "CheckPermissions", targets: ["CheckPermissions"]),
        .library(name: "DataModel", targets: ["DataModel"]),
        .library(name: "EditSettings", targets: ["EditSettings"]),
        .library(name: "Utility", targets: ["Utility"]),
    ],
    targets: [
        .target(name: "AppNavigation", dependencies: [.target(name: "CheckPermissions"), .target(name: "EditSettings")]),
        .target(name: "CheckPermissions", dependencies: [.target(name: "Utility")]),
        .target(name: "DataModel"),
        .testTarget(name: "DataModelTests", dependencies: [.target(name: "DataModel")]),
        .target(name: "EditSettings",
                dependencies: [
                    .target(name: "DataModel"),
                    .target(name: "Utility")
                ]),
        .target(name: "Utility"),
    ]
)
