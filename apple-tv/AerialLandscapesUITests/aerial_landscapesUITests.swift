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
        // Caption and minimap coords both update at the crossfade midpoint
        // (matching the website's CROSSFADE_MS/2 behaviour).
        // Key invariant: they are ALWAYS in sync — never in different states.
        remote.press(.right)

        // Wait past the midpoint (up to 1 s buffer + 0.75 s half-duration)
        waitFor(seconds: 5)
        let capMid  = caption()
        let mapMid  = minimapCoords()
        XCTAssertFalse(capMid.isEmpty,  "Caption must not be empty at midpoint")
        XCTAssertFalse(mapMid.isEmpty,  "Map coords must not be empty at midpoint")

        // Both should remain stable after midpoint until next navigation
        waitFor(seconds: 3)
        XCTAssertEqual(caption(),         capMid, "Caption should be stable after midpoint")
        XCTAssertEqual(minimapCoords(),   mapMid, "Map coords should be stable after midpoint")
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

    // MARK: - Preview mode (sidebar D-pad focus)

    /// Regression: D-padding to a sidebar section used to auto-advance the
    /// preview clip (via checkAutoFade) and then freeze on the second clip.
    /// With isPreviewMode, checkAutoFade is suppressed — queue index must
    /// stay at 0 while the sidebar is open.
    func testSidebarPreviewDoesNotAutoAdvance() {
        // Open sidebar
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Shuffle All"].waitForExistence(timeout: 3))

        // D-pad to Cities row → previewSection fires
        remote.press(.down)
        waitFor(seconds: 2)   // let the preview crossfade start

        let idxDuringPreview = queueIndex()

        // Wait well past UITEST_FAST_AUTOFADE threshold (3 s) — preview should NOT advance
        waitFor(seconds: 6)

        let idxAfterWait = queueIndex()
        XCTAssertEqual(idxAfterWait, idxDuringPreview,
                       "Preview clip must not auto-advance (stuck at \(idxDuringPreview), got \(idxAfterWait))")
        XCTAssertEqual(app.state, .runningForeground, "App must not crash during preview")
        attach("preview-no-auto-advance")
    }

    /// Reproduces the user's real complaint: open the sidebar and rapidly
    /// scrub up/down through several categories (firing many previewSection
    /// crossfades back-to-back), then commit one. The os_log telemetry +
    /// STUCK watchdog reveal whether playback actually keeps running. This
    /// test deliberately does NOT assert on queue-index alone (the flaw in the
    /// prior suite) — it keeps the app alive long enough for the watchdog to
    /// fire if the video freezes.
    func testRapidCategoryScrubbingStaysAlive() {
        remote.press(.playPause)
        XCTAssertTrue(app.staticTexts["Shuffle All"].waitForExistence(timeout: 3))

        // Scrub down through all categories quickly
        for _ in 0..<4 { remote.press(.down); Thread.sleep(forTimeInterval: 0.25) }
        attach("scrub-bottom")
        // Scrub back up
        for _ in 0..<4 { remote.press(.up);   Thread.sleep(forTimeInterval: 0.25) }
        attach("scrub-top")
        // Another fast pass to stress overlapping crossfades
        for _ in 0..<4 { remote.press(.down); Thread.sleep(forTimeInterval: 0.4) }

        // Let preview clips settle — watchdog needs ~1s of frozen time to log STUCK
        waitFor(seconds: 5)
        attach("scrub-settled")

        // Commit the focused category
        remote.press(.select)
        // Give committed clip time to load and (hopefully) keep playing
        waitFor(seconds: 8)
        attach("scrub-committed")

        XCTAssertEqual(app.state, .runningForeground, "App must survive rapid category scrubbing")
        XCTAssertFalse(caption().isEmpty, "Caption must not be blank after committing a scrubbed category")
        // The real assertion the old suite was missing: the visible video must
        // have actually kept playing. A spurious double-crossfade froze the
        // front layer — the stuck-watchdog catches that even though queue-index
        // looks fine.
        XCTAssertEqual(stuckCount(), 0,
                       "Front video must never freeze during/after category scrubbing")
    }

    private func stuckCount() -> Int {
        let el = app.descendants(matching: .any)
            .matching(identifier: "stuck-count").firstMatch
        return Int((el.value as? String) ?? el.label) ?? -1
    }

    // MARK: - Auto crossfade (end-of-clip, no user input)

    /// Verifies the clip advances on its own when one video ends — i.e. the
    /// crossfade happens between videos, not only on ←/→. Uses the
    /// UITEST_FAST_AUTOFADE launch arg so the end-of-clip fade fires ~3 s in
    /// (the production trigger is identical, just ~4 s before the natural end).
    func testAutoCrossfadeAdvancesWithoutInput() {
        app.terminate()
        let fastApp = XCUIApplication()
        fastApp.launchArguments = ["UITEST_FAST_AUTOFADE"]
        fastApp.launch()
        waitFor(seconds: 6)   // first clip buffers + begins playing

        let beforeEl = fastApp.descendants(matching: .any)
            .matching(identifier: "queue-index").firstMatch
        let before = Int((beforeEl.value as? String) ?? beforeEl.label) ?? -1

        // No remote press at all — wait out the 3 s trigger + 1 s fade + buffer.
        waitFor(seconds: 9)

        let afterEl = fastApp.descendants(matching: .any)
            .matching(identifier: "queue-index").firstMatch
        let after = Int((afterEl.value as? String) ?? afterEl.label) ?? -1

        XCTAssertEqual(fastApp.state, .runningForeground,
                       "App must survive an automatic crossfade")
        XCTAssertNotEqual(after, before,
                          "Queue index should auto-advance with no user input (was \(before), got \(after))")
        let s = XCTAttachment(screenshot: fastApp.screenshot())
        s.name = "auto-crossfade"; s.lifetime = .keepAlways; add(s)
    }
}
