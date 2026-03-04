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

    @MainActor
    func testScreenOffToggleExists() throws {
        let app = launchApp()
        let screenOffToggle = app.switches["Screen Off"]
        XCTAssertTrue(screenOffToggle.waitForExistence(timeout: 5), "Screen Off toggle should appear in section header")
    }

    @MainActor
    func testScreenOffToggleShowsTimePickers() throws {
        let app = launchApp()
        let screenOffToggle = app.switches["Screen Off"]
        XCTAssertTrue(screenOffToggle.waitForExistence(timeout: 5), "Screen Off toggle should exist")

        // Enable screen off
        if screenOffToggle.value as? String == "0" {
            screenOffToggle.tap()
        }

        // Verify the time picker controls appear
        let screenOffLabel = app.staticTexts["SCREEN OFF"]
        XCTAssertTrue(screenOffLabel.waitForExistence(timeout: 5), "SCREEN OFF label should appear when enabled")

        let screenOnLabel = app.staticTexts["SCREEN ON"]
        XCTAssertTrue(screenOnLabel.exists, "SCREEN ON label should appear when enabled")
    }

    @MainActor
    func testScreenOffToggleHidesTimePickers() throws {
        let app = launchApp()
        let screenOffToggle = app.switches["Screen Off"]
        XCTAssertTrue(screenOffToggle.waitForExistence(timeout: 5), "Screen Off toggle should exist")

        // Enable then disable
        if screenOffToggle.value as? String == "0" {
            screenOffToggle.tap()
        }
        // Now disable
        screenOffToggle.tap()

        // Verify the time picker controls disappear
        let screenOffLabel = app.staticTexts["SCREEN OFF"]
        XCTAssertFalse(screenOffLabel.exists, "SCREEN OFF label should not appear when disabled")
    }
}
