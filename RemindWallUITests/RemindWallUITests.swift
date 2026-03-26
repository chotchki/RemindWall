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

    @MainActor
    func testDeleteReminderWithButton() throws {
        let app = launchApp()

        // Wait for Settings to load
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5), "Settings should load")

        // Navigate to a trackee detail (seed data provides "Alice")
        let aliceCell = app.cells.containing(.staticText, identifier: "Alice").firstMatch
        XCTAssertTrue(aliceCell.waitForExistence(timeout: 10), "Alice trackee should appear")
        aliceCell.tap()

        // Wait for the trackee detail to load
        let deleteAliceButton = app.buttons["Delete Alice"]
        XCTAssertTrue(deleteAliceButton.waitForExistence(timeout: 10), "Alice detail screen should load")

        // Tap the add reminder button
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add button should appear")
        addButton.tap()

        // Verify Add Reminder sheet appears
        let addReminderNav = app.navigationBars["Add Reminder"]
        XCTAssertTrue(addReminderNav.waitForExistence(timeout: 5), "Add Reminder sheet should appear")

        // Save the default reminder (Sunday)
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button should appear")
        saveButton.tap()

        // Wait for the reminder row to appear
        let sundayText = app.staticTexts["Sunday"]
        XCTAssertTrue(sundayText.waitForExistence(timeout: 10), "Reminder row should appear after saving")

        // Tap the trash button to delete the reminder
        let trashButton = app.buttons["Delete Reminder"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 5), "Per-row delete button should appear")
        trashButton.tap()

        // Verify the reminder is gone
        let reminderGone = sundayText.waitForNonExistence(timeout: 5)
        XCTAssertTrue(reminderGone, "Reminder should be deleted after tapping delete button")
    }

    @MainActor
    func testAddReminderSheetStaysOpen() throws {
        let app = launchApp()

        // Wait for Settings to load
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5), "Settings should load")

        // Navigate to a trackee detail (seed data provides "Alice")
        // On Catalyst, NavigationLink in a Form may render multiple button elements;
        // use the first matching cell to navigate.
        let aliceCell = app.cells.containing(.staticText, identifier: "Alice").firstMatch
        XCTAssertTrue(aliceCell.waitForExistence(timeout: 10), "Alice trackee should appear")
        aliceCell.tap()

        // Wait for the trackee detail to load — check for content that appears on the detail screen
        let deleteButton = app.buttons["Delete Alice"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Alice detail screen should appear with Delete button")

        // Tap the add reminder button (the "+" toolbar button)
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add button should appear in toolbar")
        addButton.tap()

        // Verify the Add Reminder sheet stays visible and doesn't immediately dismiss
        let addReminderNav = app.navigationBars["Add Reminder"]
        XCTAssertTrue(addReminderNav.waitForExistence(timeout: 5), "Add Reminder sheet should stay open after tapping add button")

        // Verify key content is visible on the sheet
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.exists, "Save button should be visible on the Add Reminder sheet")

        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should be visible on the Add Reminder sheet")
    }

    @MainActor
    func testDashboardScreenLoads() throws {
        let app = launchApp()

        // Wait for Settings to load
        let startButton = app.buttons["Start Slideshow"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Slideshow button should exist")

        // Tap to navigate to Dashboard
        startButton.tap()

        // Settings nav should disappear, confirming navigation to Dashboard
        let settingsNav = app.navigationBars["Settings"]
        let settingsGone = settingsNav.waitForNonExistence(timeout: 10)
        XCTAssertTrue(settingsGone, "Settings navigation bar should disappear after starting slideshow")
    }
}
