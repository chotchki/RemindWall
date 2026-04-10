// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RWPureSwift",
    platforms: [.iOS(.v26), .macCatalyst(.v26), .macOS(.v26)],
    products: [
        .library(name: "AppModel", targets: ["AppModel"]),
        .library(name: "AppNavigation", targets: ["AppNavigation"]),
        .library(name: "AppTypes", targets: ["AppTypes"]),
        .library(name: "CalendarAsync", targets: ["CalendarAsync"]),
        .library(name: "Dashboard", targets: ["Dashboard"]),
        .library(name: "Dao", targets: ["Dao"]),
        
        .library(name: "EditSettingsNew_Reminders", targets: ["EditSettingsNew_Reminders"]),
        .library(name: "EditSettingsNew_TopLevel", targets: ["EditSettingsNew_TopLevel"]),
        .library(name: "EditSettingsNew_Trackees", targets: ["EditSettingsNew_Trackees"]),
        
        .library(name: "PhotoKitAsync", targets: ["PhotoKitAsync"]),
        .library(name: "ScreenControl", targets: ["ScreenControl"]),
        .library(name: "ScreenOffMonitor", targets: ["ScreenOffMonitor"]),
        .library(name: "Slideshow", targets: ["Slideshow"]),
        .library(name: "TagScanLoader", targets: ["TagScanLoader"]),
        .library(name: "TagScanner", targets: ["TagScanner"]),
        .library(name: "Utility", targets: ["Utility"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.6.1", traits: ["SQLiteDataTagged"]),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.31.1", traits: ["StructuredQueriesTagged"]),
        .package(
              url: "https://github.com/pointfreeco/swift-composable-architecture",
              from: "1.25.5",
              traits: [
                "ComposableArchitecture2Deprecations",
                "ComposableArchitecture2DeprecationOverloads"
              ]
            ),
        .package(url: "https://github.com/ph1ps/swift-concurrency-deadline.git", from: "1.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0")
    ],
    targets: [
        .target(name: "AppModel"),
        .target(name: "AppNavigation", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .target(name: "Dashboard"),
            .target(name: "EditSettingsNew_TopLevel"),
            .target(name: "ScreenOffMonitor"),
        ]),
        .testTarget(name: "AppNavigationTests", dependencies: [
            "AppNavigation",
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
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
        .target(name: "Dashboard", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
            .target(name: "AppTypes"),
            .target(name: "CalendarAsync"),
            .target(name: "Dao"),
            .target(name: "Slideshow"),
            .target(name: "TagScanLoader"),
            .target(name: "Utility"),
        ]),
        .testTarget(name: "DashboardTests", dependencies: [
            "Dashboard",
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
        .target(name: "Dao", dependencies: [
            .product(
                name: "Dependencies",
                package: "swift-dependencies"
              ),
            .product(name: "SQLiteData", package: "sqlite-data"),
            .target(name: "AppTypes"),
        ]),
        .testTarget(name: "DaoTests", dependencies: ["Dao", .product(name: "DependenciesTestSupport", package: "swift-dependencies")]),
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
        .testTarget(name: "PhotoKitAsyncTests", dependencies: ["PhotoKitAsync", .product(name: "DependenciesTestSupport", package: "swift-dependencies")]),
        .target(name: "ScreenControl", dependencies: [
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "DependenciesMacros", package: "swift-dependencies"),
        ]),
        .target(name: "ScreenOffMonitor", dependencies: [
            .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .target(name: "AppTypes"),
            .target(name: "ScreenControl"),
        ]),
        .testTarget(name: "ScreenOffMonitorTests", dependencies: [
            "ScreenOffMonitor",
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
        .target(name: "Slideshow",
                dependencies: [
                    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                    .target(name: "AppTypes"),
                    .target(name: "PhotoKitAsync"),
                ],
                resources: [.process("Widget/Resources/PreviewAssets.xcassets")]),
        .testTarget(name: "SlideshowTests", dependencies: [
            "Slideshow",
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
        .target(name: "TagScanLoader",
                dependencies: [
                    .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                    .product(name: "StructuredQueries", package: "swift-structured-queries"),
                    .target(name: "AppTypes"),
                    .target(name: "Dao"),
                    .target(name: "TagScanner"),
                ]),
        .testTarget(name: "TagScanLoaderTests", dependencies: [
            "TagScanLoader",
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
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
        .testTarget(name: "TagScannerTests", dependencies: [
            "TagScanner",
            .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        ]),
        .target(name: "Utility"),
    ]
)
