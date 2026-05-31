//
//  aerial_landscapesUITests.swift
//  AerialLandscapesUITests
//
//  XCUITest suite for the AerialLandscapes tvOS app.
//  Uses XCUIRemote to simulate Siri Remote input.
//  Screenshots are attached as test artifacts for visual review.
//

import XCTest

final class AerialLandscapesUITests: XCTestCase {

    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Give the first video time to buffer before testing
        waitForVideo(seconds: 6)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Launch

    func testLaunchAndVideoPlays() {
        XCTAssertEqual(app.state, .runningForeground, "App should be running")
        attach(label: "after-launch")
        // Caption text should be visible (a non-empty StaticText)
        let caption = app.staticTexts.element(boundBy: 0)
        XCTAssertTrue(caption.exists, "Caption should be present on launch")
    }

    // MARK: - Single navigation

    func testForwardNavigation() {
        // Catalog has duplicate titles (e.g. "Mont Saint-Michel" x4), so we
        // can't assert the caption changes. Instead: verify no crash + screenshot.
        remote.press(.right)
        waitForVideo(seconds: 2)
        XCTAssertEqual(app.state, .runningForeground, "App should still be running after →")
        attach(label: "after-forward")
        // Caption must be non-empty (not blank or cleared)
        XCTAssertFalse(firstCaption().isEmpty, "Caption should not be empty after →")
    }

    func testBackwardNavigation() {
        remote.press(.right)
        waitForVideo(seconds: 2)
        remote.press(.left)
        waitForVideo(seconds: 2)
        XCTAssertEqual(app.state, .runningForeground, "App should still be running after ←")
        attach(label: "after-backward")
        XCTAssertFalse(firstCaption().isEmpty, "Caption should not be empty after ←")
    }

    // MARK: - Rapid navigation (the main regression test)

    func testRapidForwardSpam() {
        // Press → 10 times in quick succession with only 120ms between presses
        for i in 0..<10 {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.12)
            if i == 4 { attach(label: "rapid-forward-mid") }
        }
        waitForVideo(seconds: 3)
        XCTAssertEqual(app.state, .runningForeground, "App should survive 10 rapid → presses")
        attach(label: "rapid-forward-final")
        // Caption should be non-empty — not blank or showing wrong video title
        let cap = firstCaption()
        XCTAssertFalse(cap.isEmpty, "Caption should not be empty after rapid navigation")
    }

    func testRapidBackwardSpam() {
        // Advance first so backward has room
        remote.press(.right)
        waitForVideo(seconds: 2)

        for i in 0..<10 {
            remote.press(.left)
            Thread.sleep(forTimeInterval: 0.12)
            if i == 4 { attach(label: "rapid-backward-mid") }
        }
        waitForVideo(seconds: 3)
        XCTAssertEqual(app.state, .runningForeground, "App should survive 10 rapid ← presses")
        attach(label: "rapid-backward-final")
    }

    func testAlternatingForwardBackward() {
        // Most destructive pattern: toggle direction on every press
        for i in 0..<12 {
            if i % 2 == 0 { remote.press(.right) } else { remote.press(.left) }
            Thread.sleep(forTimeInterval: 0.15)
        }
        waitForVideo(seconds: 3)
        XCTAssertEqual(app.state, .runningForeground,
                       "App should survive alternating ←/→ presses")
        attach(label: "alternating-nav-final")
        let cap = firstCaption()
        XCTAssertFalse(cap.isEmpty, "Caption should not be blank after alternating navigation")
    }

    // MARK: - Sidebar

    func testSidebarOpens() {
        remote.press(.playPause)
        waitForVideo(seconds: 1)
        XCTAssertEqual(app.state, .runningForeground)
        attach(label: "sidebar-open")
        // The sidebar contains "Shuffle All" and section names as UILabel text
        let shuffleLabel = app.staticTexts["Shuffle All"]
        XCTAssertTrue(shuffleLabel.waitForExistence(timeout: 2),
                      "Sidebar should show 'Shuffle All' item")
    }

    func testSidebarClosesWithMenu() {
        remote.press(.playPause)
        let shuffleItem = app.staticTexts["Shuffle All"]
        XCTAssertTrue(shuffleItem.waitForExistence(timeout: 2), "Sidebar should open")
        remote.press(.menu)
        waitForVideo(seconds: 1)
        XCTAssertEqual(app.state, .runningForeground)
        attach(label: "sidebar-closed")
        // isHittable=false means the element is off-screen (sidebar slid away).
        // .exists alone is insufficient because off-screen cells still exist in
        // the view hierarchy.
        XCTAssertFalse(app.staticTexts["Shuffle All"].isHittable,
                       "Sidebar items should not be hittable when closed")
    }

    func testSidebarSelectCoastal() {
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Shuffle All"].waitForExistence(timeout: 2))
        // Navigate down: Shuffle All → Cities → Coastal
        remote.press(.down); Thread.sleep(forTimeInterval: 0.3)
        remote.press(.down); Thread.sleep(forTimeInterval: 0.3)
        remote.press(.select)
        waitForVideo(seconds: 3)
        XCTAssertEqual(app.state, .runningForeground)
        attach(label: "after-coastal-select")
        XCTAssertFalse(app.staticTexts["Shuffle All"].isHittable,
                       "Sidebar should not be hittable after selection")
    }

    // MARK: - No-black-frame check
    //
    // We can't programmatically measure pixel darkness, but we attach
    // screenshots immediately after transitions so they can be reviewed
    // manually in Xcode's test results.

    func testNoBlackFrameAfterNavigation() {
        for i in 1...5 {
            remote.press(.right)
            waitForVideo(seconds: 1.5)
            attach(label: "frame-check-\(i)")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Helpers

    private func waitForVideo(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func firstCaption() -> String {
        // The caption SwiftUI Text is the largest StaticText on screen
        return app.staticTexts.allElementsBoundByIndex
            .first(where: { !$0.label.isEmpty })?
            .label ?? ""
    }

    private func attach(label: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
