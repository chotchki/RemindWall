//
//  RemindWalliOSUITests.swift
//  RemindWalliOSUITests
//
//  Created by Christopher Hotchkiss on 3/2/26.
//

import XCTest

final class RemindWalliOSUITests: XCTestCase {

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
    func testSlideshowNotConfiguredAndReturnToSettings() throws {
        let app = launchApp()

        // Navigate to Dashboard
        let startButton = app.buttons["Start Slideshow"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start Slideshow button should exist")
        startButton.tap()

        // In UI test mode (in-memory storage), no album is selected.
        // The slideshow shows a "Return to Settings" button in the not-configured state.
        let returnButton = app.buttons["Return to Settings"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 10),
                      "Return to Settings button should appear on the slideshow screen")

        // Tap to navigate back
        returnButton.tap()

        // Verify we're back on the Settings screen
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 10),
                      "Settings navigation bar should reappear after returning from slideshow")
    }

    @MainActor
    func testSlideshowAdvancesPhotos() throws {
        let app = launchApp()

        // Handle photo library permission dialog if it appears
        addUIInterruptionMonitor(withDescription: "Photo Library Access") { alert in
            let allowButton = alert.buttons["Allow Full Access"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            let okButton = alert.buttons["OK"]
            if okButton.exists {
                okButton.tap()
                return true
            }
            return false
        }

        // Wait for Settings to load
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5), "Settings should load")

        // Enable the Slideshow toggle if not already on
        let slideshowToggle = app.switches["Slideshow"]
        XCTAssertTrue(slideshowToggle.waitForExistence(timeout: 5), "Slideshow toggle should exist")
        if slideshowToggle.value as? String == "0" {
            slideshowToggle.tap()
        }

        // If photo authorization is needed, tap "Authorize Photo Access" first
        let authButton = app.buttons["Authorize Photo Access"]
        if authButton.waitForExistence(timeout: 3) {
            authButton.tap()
            app.tap() // trigger interruption monitor for system dialog
        }

        // Wait for albums to load and the picker to appear.
        // On iOS the Picker("Albums",...) with .navigationLink style renders as a button.
        let albumButton = app.buttons["Albums"]
        XCTAssertTrue(albumButton.waitForExistence(timeout: 15),
                      "Album picker should appear (photo library must be authorized)")

        // Tap the Albums picker - on iOS this pushes a navigation view with album options
        albumButton.tap()

        // On iOS, the navigationLink picker pushes a list/collection with album cells.
        let pickerCollection = app.collectionViews.firstMatch
        XCTAssertTrue(pickerCollection.waitForExistence(timeout: 5),
                      "Picker should push a collection view with album options")

        let albumButtons = pickerCollection.buttons
        XCTAssertTrue(albumButtons.count >= 2,
                      "At least 2 album buttons should be available (found \(albumButtons.count))")

        // Tap the second album button to ensure it's a different selection
        albumButtons.element(boundBy: 1).tap()

        // On iOS, the picker may not auto-navigate back.
        // If "Start Slideshow" doesn't appear, tap the Back button.
        let startButton = app.buttons["Start Slideshow"]
        if !startButton.waitForExistence(timeout: 3) {
            let backButton = app.navigationBars.buttons["Settings"]
            if backButton.exists {
                backButton.tap()
            }
        }

        // Wait for "Start Slideshow" to become available
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Start Slideshow button should exist after selecting album")
        startButton.tap()

        // Verify we navigated to the Dashboard.
        let dashboard = app.descendants(matching: .any)["DashboardView"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 15),
                      "Dashboard should appear after starting slideshow")

        // Wait for a photo to load - the dashboard's value will contain the asset identifier
        let hasValue = NSPredicate(format: "value != nil AND value != ''")
        let valueLoaded = XCTNSPredicateExpectation(predicate: hasValue, object: dashboard)
        let loadResult = XCTWaiter.wait(for: [valueLoaded], timeout: 15)
        XCTAssertEqual(loadResult, .completed,
                       "Dashboard should load a photo with an asset identifier value")

        // Record the initial photo's accessibility value
        let initialValue = dashboard.value as? String ?? ""
        XCTAssertFalse(initialValue.isEmpty,
                       "Dashboard should have a value with the asset identifier")

        // Wait for the slideshow to advance (timer is 10 seconds + buffer)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialValue),
            object: dashboard
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 20)
        XCTAssertEqual(result, .completed,
                       "Slideshow should advance to a different photo within 20 seconds")
    }

    @MainActor
    func testTapSlideshowReturnsToSettings() throws {
        let app = launchApp()

        // Handle photo library permission dialog if it appears
        addUIInterruptionMonitor(withDescription: "Photo Library Access") { alert in
            let allowButton = alert.buttons["Allow Full Access"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            let okButton = alert.buttons["OK"]
            if okButton.exists {
                okButton.tap()
                return true
            }
            return false
        }

        // Wait for Settings to load
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5), "Settings should load")

        // Enable the Slideshow toggle if not already on
        let slideshowToggle = app.switches["Slideshow"]
        XCTAssertTrue(slideshowToggle.waitForExistence(timeout: 5), "Slideshow toggle should exist")
        if slideshowToggle.value as? String == "0" {
            slideshowToggle.tap()
        }

        // If photo authorization is needed, tap "Authorize Photo Access" first
        let authButton = app.buttons["Authorize Photo Access"]
        if authButton.waitForExistence(timeout: 3) {
            authButton.tap()
            app.tap()
        }

        // Select an album
        let albumButton = app.buttons["Albums"]
        XCTAssertTrue(albumButton.waitForExistence(timeout: 15),
                      "Album picker should appear")
        albumButton.tap()

        let pickerCollection = app.collectionViews.firstMatch
        XCTAssertTrue(pickerCollection.waitForExistence(timeout: 5),
                      "Picker should push a collection view")

        let albumButtons = pickerCollection.buttons
        XCTAssertTrue(albumButtons.count >= 2,
                      "At least 2 album buttons should be available")
        albumButtons.element(boundBy: 1).tap()

        let startButton = app.buttons["Start Slideshow"]
        if !startButton.waitForExistence(timeout: 3) {
            let backButton = app.navigationBars.buttons["Settings"]
            if backButton.exists {
                backButton.tap()
            }
        }

        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Start Slideshow button should exist after selecting album")
        startButton.tap()

        // Wait for the Dashboard with a loaded photo
        let dashboard = app.descendants(matching: .any)["DashboardView"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 15),
                      "Dashboard should appear after starting slideshow")

        let hasValue = NSPredicate(format: "value != nil AND value != ''")
        let valueLoaded = XCTNSPredicateExpectation(predicate: hasValue, object: dashboard)
        let loadResult = XCTWaiter.wait(for: [valueLoaded], timeout: 15)
        XCTAssertEqual(loadResult, .completed,
                       "Dashboard should load a photo")

        // Tap the slideshow image to return to settings
        dashboard.tap()

        // Verify we're back on the Settings screen
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 10),
                      "Settings should reappear after tapping the slideshow")
    }

    @MainActor
    func testAddReminderSheetStaysOpen() throws {
        let app = launchApp()

        // Wait for Settings to load
        let settingsNav = app.navigationBars["Settings"]
        XCTAssertTrue(settingsNav.waitForExistence(timeout: 5), "Settings should load")

        // Navigate to a trackee detail (seed data provides "Alice")
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
}
