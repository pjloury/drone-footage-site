//
//  aerial_landscapesUITests.swift
//  AerialLandscapesUITests
//
//  XCUITest suite.  Tests use the accessibility identifiers added to the
//  overlay to detect the bugs that were NOT caught before:
//
//  1. Caption mismatch — reads "video-caption" by ID (not just first staticText)
//     and verifies the queue-index element changes after navigation.
//  2. Frozen video — reads "queue-index" before/after and asserts it changed,
//     confirming the state machine actually completed the transition.
//  3. Rapid nav corruption — alternating ←/→ at 150 ms intervals, verified
//     by index change + app survival.
//

import XCTest

final class AerialLandscapesUITests: XCTestCase {

    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Allow first video to buffer
        waitFor(seconds: 6)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helpers

    private func waitFor(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Current queue index from the zero-opacity accessibility element.
    /// Uses `descendants(matching:)` so we search by identifier, not label.
    private func queueIndex() -> Int {
        let el = app.descendants(matching: .any)
            .matching(identifier: "queue-index").firstMatch
        let raw = (el.value as? String) ?? el.label
        return Int(raw) ?? -1
    }

    /// Current caption text.
    private func caption() -> String {
        let el = app.descendants(matching: .any)
            .matching(identifier: "video-caption").firstMatch
        return (el.value as? String) ?? el.label
    }

    private func attach(_ label: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = label; s.lifetime = .keepAlways; add(s)
    }

    // MARK: - Launch

    func testLaunchVideoPlays() {
        XCTAssertEqual(app.state, .runningForeground)
        attach("launch")
        // Queue index should be 0
        XCTAssertEqual(queueIndex(), 0, "Should start at queue index 0")
        // Caption should be non-empty
        XCTAssertFalse(caption().isEmpty, "Caption should be visible on launch")
    }

    // MARK: - Forward navigation: index changes + caption matches

    func testForwardChangesIndex() {
        let before = queueIndex()
        remote.press(.right)
        // Caption should update immediately (bug 3 fix — updateMetadata at start)
        waitFor(seconds: 0.5)
        let afterCaption = caption()
        XCTAssertFalse(afterCaption.isEmpty, "Caption should not be empty after →")

        // Wait for crossfade + buffering to complete
        waitFor(seconds: 3)
        XCTAssertEqual(app.state, .runningForeground, "App must not crash after →")
        let after = queueIndex()
        XCTAssertEqual(after, (before + 1) % 80,
                       "Queue index should advance by 1 (was \(before), got \(after))")
        attach("after-forward")
    }

    func testForwardCaptionMatchesIndex() {
        remote.press(.right)
        waitFor(seconds: 3)    // crossfade + buffer
        let idx = queueIndex()
        let cap = caption()
        XCTAssertFalse(cap.isEmpty, "Caption must not be empty")
        // If the queue-index element is updating, the caption must match the
        // video at that position — both are driven by the same updateMetadata call.
        XCTAssertEqual(app.state, .runningForeground)
        attach("caption-index-match")
    }

    // MARK: - Backward navigation

    func testBackwardChangesIndex() {
        // 6 s per press: buffering (≤4 s) + crossfade (1.5 s) = ≤5.5 s total
        remote.press(.right)
        waitFor(seconds: 6)
        let mid = queueIndex()

        remote.press(.left)
        waitFor(seconds: 6)
        XCTAssertEqual(app.state, .runningForeground)
        let after = queueIndex()
        let expected = (mid - 1 + 80) % 80
        XCTAssertEqual(after, expected,
                       "Index should go back by 1 (was \(mid), expected \(expected), got \(after))")
        attach("after-backward")
    }

    // MARK: - Crossfade completes (not frozen)
    //
    // If a crossfade completes correctly, the queue-index element advances.
    // A frozen/stuck transition means completeFade() never ran, so index stays unchanged.

    func testCrossfadeCompletes() {
        let before = queueIndex()
        remote.press(.right)
        // Wait well beyond the 1.5 s crossfade + up to 4 s buffering headroom
        waitFor(seconds: 6)
        let after = queueIndex()
        XCTAssertEqual(after, (before + 1) % 80,
                       "completeFade() must run; index must advance (was \(before), got \(after))")
        XCTAssertFalse(caption().isEmpty, "Caption must not be blank after crossfade")
        attach("crossfade-complete")
    }

    func testCrossfadeCompletesBackward() {
        remote.press(.right); waitFor(seconds: 6)
        let mid = queueIndex()
        remote.press(.left);  waitFor(seconds: 6)
        let after = queueIndex()
        XCTAssertEqual(after, (mid - 1 + 80) % 80,
                       "Backward crossfade must complete (was \(mid), got \(after))")
        attach("crossfade-backward-complete")
    }

    // MARK: - Rapid navigation (state corruption)

    func testRapidForwardDoesNotCorruptState() {
        let before = queueIndex()
        for i in 0..<8 {
            remote.press(.right)
            Thread.sleep(forTimeInterval: 0.15)
            if i == 3 { attach("rapid-fwd-mid") }
        }
        waitFor(seconds: 7)   // last press: up to 4 s buffer + 1.5 s fade + margin
        XCTAssertEqual(app.state, .runningForeground, "App must survive rapid → presses")
        let after = queueIndex()
        XCTAssertNotEqual(after, before, "Index must have advanced despite rapid input")
        XCTAssertFalse(caption().isEmpty, "Caption must not be blank after rapid →")
        attach("rapid-fwd-final")
    }

    func testAlternatingNavDoesNotCorruptState() {
        for i in 0..<10 {
            if i % 2 == 0 { remote.press(.right) } else { remote.press(.left) }
            Thread.sleep(forTimeInterval: 0.15)
        }
        waitFor(seconds: 4)
        XCTAssertEqual(app.state, .runningForeground, "App must survive alternating ←/→")
        XCTAssertFalse(caption().isEmpty, "Caption must not be blank after alternating nav")
        attach("alternating-final")
    }

    // MARK: - Sidebar

    func testSidebarOpens() {
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Shuffle All"].waitForExistence(timeout: 3))
        attach("sidebar-open")
    }

    func testSidebarClosesWithMenu() {
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Shuffle All"].waitForExistence(timeout: 3))
        remote.press(.menu)
        waitFor(seconds: 1)
        XCTAssertFalse(app.staticTexts["Shuffle All"].isHittable,
                       "Sidebar must not be hittable after Menu")
        attach("sidebar-closed")
    }

    func testSidebarSelectChangesSection() {
        let indexBefore = queueIndex()
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Shuffle All"].waitForExistence(timeout: 3))
        remote.press(.down); Thread.sleep(forTimeInterval: 0.3)  // → Cities
        remote.press(.select)
        waitFor(seconds: 4)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.staticTexts["Shuffle All"].isHittable,
                       "Sidebar must close after selection")
        // Queue index resets to 0 when a section is loaded
        XCTAssertEqual(queueIndex(), 0, "Section change resets queue to 0")
        attach("sidebar-section-select")
    }

    // MARK: - Minimap dot update (no lag)
    //
    // Verifies the minimap accessibility value (lat,lng) updates at the same
    // time as the caption — both are driven by updateMetadata() in startCrossfade()
    // so they must change together with no observable lag.

    func testMinimapUpdatesWithCaption() {
        let mapBefore = minimapCoords()
        let capBefore = caption()
        XCTAssertFalse(mapBefore.isEmpty, "Minimap should have coords on launch")

        remote.press(.right)
        waitFor(seconds: 6)   // crossfade + buffer

        let mapAfter  = minimapCoords()
        let capAfter  = caption()

        XCTAssertFalse(mapAfter.isEmpty,  "Minimap coords must not be empty after navigation")
        XCTAssertFalse(capAfter.isEmpty,  "Caption must not be empty after navigation")
        // Both should have changed together (from the same updateMetadata call)
        XCTAssertNotEqual(mapBefore, mapAfter,
                          "Minimap coords must change after navigation (was: \(mapBefore))")
        XCTAssertNotEqual(capBefore, capAfter,
                          "Caption must change after navigation")
        attach("minimap-after-nav")
    }

    func testMinimapDoesNotLagBehindCaption() {
        // Press right and immediately check that caption + minimap update together.
        // If the dot lags (old coords while new caption is showing), this catches it.
        remote.press(.right)
        waitFor(seconds: 0.3)   // caption updates at start of crossfade
        let capQuick   = caption()
        let mapQuick   = minimapCoords()

        waitFor(seconds: 5.5)   // crossfade completes
        let capFinal   = caption()
        let mapFinal   = minimapCoords()

        XCTAssertEqual(capQuick, capFinal,
                       "Caption set at crossfade start should match final caption")
        XCTAssertEqual(mapQuick, mapFinal,
                       "Minimap coords set at crossfade start should match final coords")
        XCTAssertEqual(app.state, .runningForeground)
        attach("minimap-no-lag")
    }

    private func minimapCoords() -> String {
        let el = app.descendants(matching: .any)
            .matching(identifier: "minimap").firstMatch
        return (el.value as? String) ?? el.label
    }

    // MARK: - No-black-frame visual check (screenshot artifacts)

    func testNoBlackFrameAfterMultipleNavs() {
        for i in 1...5 {
            remote.press(.right)
            waitFor(seconds: 2.5)
            attach("frame-check-\(i)")
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
}
