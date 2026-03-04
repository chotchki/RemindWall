//
//  RemindWallUITests.swift
//  RemindWallUITests
//
//  Created by Christopher Hotchkiss on 3/2/26.
//

import XCTest

final class RemindWallUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITesting"] = "true"
        app.launch()
        return app
    }

    @MainActor
    func testSettingsScreenLoads() throws {
        let app = launchApp()
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5), "Settings navigation bar should appear")
    }

    @MainActor
    func testStartSlideshowButtonExists() throws {
        let app = launchApp()
        let startButton = app.buttons["Start Slideshow"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Slideshow button should exist")
    }
}
