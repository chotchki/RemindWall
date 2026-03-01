// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RWPureSwift",
    platforms: [.iOS(.v26), .macCatalyst(.v26), .macOS(.v26)],
    products: [
        .library(name: "AppModel", targets: ["AppModel"]),
        .library(name: "AppTypes", targets: ["AppTypes"]),
        .library(name: "CalendarAsync", targets: ["CalendarAsync"]),
        //.library(name: "Dashboard", targets: ["Dashboard"]),
        .library(name: "Dao", targets: ["Dao"]),
        
        .library(name: "EditSettingsNew_Reminders", targets: ["EditSettingsNew_Reminders"]),
        .library(name: "EditSettingsNew_TopLevel", targets: ["EditSettingsNew_TopLevel"]),
        .library(name: "EditSettingsNew_Trackees", targets: ["EditSettingsNew_Trackees"]),
        
        .library(name: "PhotoKitAsync", targets: ["PhotoKitAsync"]),
        //.library(name: "Slideshow", targets: ["Slideshow"]),
        .library(name: "TagScanner", targets: ["TagScanner"]),
        .library(name: "Utility", targets: ["Utility"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.5.1", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.30.0", traits: ["StructuredQueriesTagged"]),
        .package(
              url: "https://github.com/pointfreeco/swift-composable-architecture",
              from: "1.23.1"
            ),
        .package(url: "https://github.com/ph1ps/swift-concurrency-deadline.git", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0")
    ],
    targets: [
        .target(name: "AppModel"),
        .target(name: "AppTypes", dependencies: [
            .product(name: "SQLiteData", package: "sqlite-data"),
            .product(name:"Tagged", package: "swift-tagged"),
        ]),
        .testTarget(name: "AppTypesTests", dependencies: [
            .target(name: "AppTypes"),
        ]),
        .target(name: "CalendarAsync", dependencies: [
            .product(
              name: "Dependencies",
              package: "swift-dependencies"
            ),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
            .target(name: "AppTypes"),
        ]),
        //.target(name: "Dashboard", dependencies: [
        //    .target(name: "DataModel"),
        //    .target(name: "Slideshow"),
        //    .target(name: "Utility")
        //]),
        .target(name: "Dao", dependencies: [
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .target(name: "AppTypes"),
        ]),
        .testTarget(name: "DaoTests", dependencies: ["Dao"]),
        .target(name: "EditSettingsNew_Reminders",dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .target(name: "Dao"),
            .target(name: "TagScanner")
        ], path: "Sources/EditSettingsNew/Reminders"),
        .testTarget(name: "EditSettingsNew_RemindersTests",
                    dependencies: [
                        "EditSettingsNew_Reminders",
                        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
                    ], path: "Tests/EditSettingsNewTests/Reminders"),
        
        .target(name: "EditSettingsNew_TopLevel",dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .target(name: "CalendarAsync"),
            .target(name: "Dao"),
            .target(name: "EditSettingsNew_Trackees"),
            .target(name: "PhotoKitAsync"),
        ], path: "Sources/EditSettingsNew/TopLevel"),
        .testTarget(name: "EditSettingsNew_TopLevelTests",
                    dependencies: [
                        "EditSettingsNew_TopLevel",
                        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
                    ], path: "Tests/EditSettingsNewTests/TopLevel"),
        
        .target(name: "EditSettingsNew_Trackees",dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .target(name: "Dao"),
            .target(name: "EditSettingsNew_Reminders")
        ], path: "Sources/EditSettingsNew/Trackees"),
        .testTarget(name: "EditSettingsNew_TrackeesTests",
                    dependencies: [
                        "EditSettingsNew_Trackees",
                        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
                    ], path: "Tests/EditSettingsNewTests/Trackees"),
        
        .target(name: "PhotoKitAsync", dependencies: [
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
            .product(name:"Tagged", package: "swift-tagged"),
            .target(name: "AppTypes"),
            .target(name: "Dao"),
        ]),
        .testTarget(name: "PhotoKitAsyncTests", dependencies: ["PhotoKitAsync"]),
//        .target(name: "Slideshow",
//                dependencies: [
//                    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
//                    .target(name: "AppModel"),
//                    .target(name: "DataModel"),
//                    .target(name: "PhotoKitAsync"),
//                    .target(name: "Utility"),
//                ], 
//                resources:[ .process("Widget/Resources/PreviewAssets.xcassets")]),
        .target(name: "TagScanner",
                dependencies: [
                    .target(name: "AppTypes"),
                    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                    .product(name: "Deadline", package: "swift-concurrency-deadline"),
                    .product(
                      name: "Dependencies",
                      package: "swift-dependencies"
                    ),
                    .product(name: "DependenciesMacros", package: "swift-dependencies"),
                ]),
        .testTarget(name: "TagScannerTests", dependencies: [.target(name: "TagScanner")]),
        .target(name: "Utility"),
    ]
)
