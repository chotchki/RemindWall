// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RWPureSwift",
    platforms: [.iOS(.v17), .macCatalyst(.v17)],
    products: [
        .library(name: "AppNavigation", targets: ["AppNavigation"]),
        .library(name: "CheckPermissions", targets: ["CheckPermissions"]),
        .library(name: "Dashboard", targets: ["Dashboard"]),
        .library(name: "DataModel", targets: ["DataModel"]),
        .library(name: "EditSettings", targets: ["EditSettings"]),
        .library(name: "Utility", targets: ["Utility"]),
    ],
    dependencies: [
        .package(url: "https://github.com/chotchki/LibNFCSwift.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "AppNavigation", dependencies: [
            .target(name: "CheckPermissions"),
            .target(name: "Dashboard"),
            .target(name: "EditSettings")
        ]),
        .target(name: "CheckPermissions", dependencies: [
            .target(name: "DataModel"),
            .target(name: "Utility")
        ]),
        .target(name: "Dashboard", dependencies: [
            .target(name: "DataModel"),
            .target(name: "Utility")
        ]),
        .target(name: "DataModel"),
        .testTarget(name: "DataModelTests", dependencies: [.target(name: "DataModel")]),
        .target(name: "EditSettings",
                dependencies: [
                    .product(name: "LibNFCSwift", package: "LibNFCSwift" , condition: .when(platforms: [.macCatalyst])),
                    .target(name: "DataModel"),
                    .target(name: "Utility"),
                    
                ]),
        .target(name: "Utility"),
    ]
)
