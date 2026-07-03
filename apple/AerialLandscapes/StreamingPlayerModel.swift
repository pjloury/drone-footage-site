//
//  StreamingPlayerModel.swift
//  AerialLandscapes
//
//  Two-player crossfade engine — three-bug rewrite.
//
//  Bug 1 fixed: layer cleanup race
//    performCrossfade() no longer has an asyncAfter cleanup.
//    finalizeLayersCallback is called inside completeFade() AFTER
//    isFrontA.toggle(), so PlayerVC always reads the correct state.
//
//  Bug 2 fixed: preloaded item destroyed on every manual skip
//    startCrossfade checks whether backPlayer already has the target
//    URL loaded (from preloadBack). If it does, we reuse it and skip
//    the replaceCurrentItem+seek sequence, giving the user instant playback.
//
//  Bug 3 fixed: caption updated too late / wrong player state
//    Caption updates at the START of crossfadeCallback (when the new
//    video begins fading in) rather than only on completeFade().
//

import AVFoundation
import SwiftUI
import os

// MARK: - Telemetry
//
// All crossfade/preview state transitions log to this subsystem so we can
// stream them from the simulator and see EXACTLY what the engine did:
//   xcrun simctl spawn booted log stream --style compact \
//     --predicate 'subsystem == "com.aeriallandscapes.crossfade"'
// Critically, this includes a playback STUCK watchdog that measures actual
// currentTime advancement on the visible front player — not just whether the
// queue-index state machine completed. A "stuck video" is precisely the case
// where completeFade() ran (index advanced) yet currentTime is frozen.
let xfadeLog = Logger(subsystem: "com.aeriallandscapes.crossfade", category: "engine")

// MARK: - StreamingPlayerModel

class StreamingPlayerModel: ObservableObject {

    // ── Two players ───────────────────────────────────────────────────────
    let playerA = AVPlayer()
    let playerB = AVPlayer()

    private(set) var isFrontA = true
    var frontPlayer: AVPlayer { isFrontA ? playerA : playerB }
    var backPlayer:  AVPlayer { isFrontA ? playerB : playerA }

    // ── Callbacks (set by PlayerViewController) ───────────────────────────
    /// Fired with the crossfade duration when a fade should start.
    var crossfadeCallback: ((TimeInterval) -> Void)?
    /// Fired when a crossfade is cancelled — VC snaps layers to a clean baseline.
    var resetLayersCallback: (() -> Void)?
    /// Fired inside completeFade() AFTER isFrontA.toggle() — VC finalises opacities.
    var finalizeLayersCallback: (() -> Void)?

    // ── Published state ───────────────────────────────────────────────────
    @Published private(set) var currentTitle = ""
    @Published private(set) var currentQueueIndex = 0   // exposed for UI tests

    // Number of times the stuck-watchdog has detected the visible front player
    // frozen (currentTime not advancing while it should be playing). Surfaced as
    // a hidden accessibility value so UI tests can assert it stays 0 — the prior
    // suite could only see the queue-index state machine, never actual playback,
    // which is why a frozen frame passed every test.
    @Published private(set) var stuckEventCount = 0
    @Published private(set) var activeSection: String? = nil

    // Tracks the last user-confirmed section (committed via Select or initial load).
    // previewSection() changes activeSection without touching committedSection;
    // cancelPreview() reverts activeSection back to committedSection.
    private(set) var committedSection: String? = nil

    // True while the user is browsing the sidebar without committing a section.
    // Suppresses auto-crossfade so preview clips don't auto-advance.
    private var isPreviewMode = false
    @Published private(set) var currentLat: Double? = nil
    @Published private(set) var currentLng: Double? = nil
    @Published var leftFlash     = false
    @Published var rightFlash    = false
    /// Horizontal offset applied to bottom-left UI (caption, minimap) when
    /// the sidebar slides in, so they don't straddle the sidebar edge.
    @Published var captionOffset: CGFloat = 0

    /// Single source of truth for the visibility of ALL bottom overlay chrome
    /// (caption, minimap, progress bar — and any component added later).
    ///
    /// CONVENTION — keep the overlay seamless: every on-screen overlay element
    /// must bind its opacity to `overlayVisible` and animate with
    /// `overlayFadeDuration`, so the whole overlay fades OUT together when a
    /// crossfade starts and fades IN together at the crossfade midpoint (after
    /// the new clip's metadata/map/progress have been swapped in while
    /// invisible). Mirrors the website, which toggles a `.fade`/`.visible`
    /// class on each overlay element in lock-step with the video crossfade.
    /// When you add a new overlay view, wire it to these two — do not give it
    /// its own independent fade.
    @Published var overlayVisible = true
    static let overlayFadeDuration: TimeInterval = 0.6

    /// Playback progress (0…1) of the current front clip, driving the thin
    /// bottom progress bar — mirrors the website's #bar width.
    @Published var playbackProgress: Double = 0

    // ── Sections ──────────────────────────────────────────────────────────
    static let sections: [(id: String, name: String)] = [
        ("cities",    "Cities"),
        ("coastal",   "Coastal"),
        ("mountains", "Mountains"),
        ("desert",    "Desert"),
    ]

    // ── Queue ─────────────────────────────────────────────────────────────
    private var queue: [Video] = []

    // ── Crossfade state ───────────────────────────────────────────────────
    private var crossfadeGeneration = 0
    private var isCrossfading  = false
    private var autoFadeArmed  = false

    private var timeObserver: Any?
    private var timeObserverOwner: AVPlayer?
    private var bufferingObservation: NSKeyValueObservation?

    // Stuck-watchdog state: tracks whether the VISIBLE front player's currentTime
    // is actually advancing. The queue-index state machine can complete while the
    // on-screen video is frozen — this is the symptom the old tests could not see.
    private var lastWatchdogTime: Double = -1
    private var stalledTicks = 0
    private var loggedStuck = false

    static let autoDuration:   TimeInterval = 4.0
    static let manualDuration: TimeInterval = 1.5   // slightly longer for buffering headroom

    // UI-test accelerant: when launched with "UITEST_FAST_AUTOFADE", the
    // end-of-clip auto-crossfade fires a few seconds in (instead of ~4 s
    // before the clip's natural end) so a test can confirm auto-advance
    // happens with no user input, without waiting out an 89 s clip.
    // The crossfade itself is identical to production — only the trigger
    // threshold changes.
    private let fastAutoFade =
        ProcessInfo.processInfo.arguments.contains("UITEST_FAST_AUTOFADE")

    // MARK: Init

    init() {
        // Mix with whatever is already playing (e.g. AirPlay audio from another
        // app) rather than interrupting it. The aerial footage is visual-only —
        // both players stay muted for the lifetime of the app.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        playerA.isMuted = true
        playerB.isMuted = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)

        loadSection(nil)

        // Upgrade to the shared cloud catalog in the background; if it brings
        // new videos, rebuild the current section's queue. Falls back silently
        // to the bundled catalog on any failure.
        Task { @MainActor [weak self] in
            let changed = await VideoConfig.load()
            guard let self, changed else { return }
            self.loadSection(self.committedSection)
        }
    }

    @objc private func appDidBecomeActive() {
        frontPlayer.play()
        // After a background stint the player's buffer may have been evicted.
        // Give AVPlayer a moment to resume; if it's still not playing, reload
        // the current clip from the top so we're never stuck on a frozen frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let tcs = self.frontPlayer.timeControlStatus
            let itemBroken = self.frontPlayer.currentItem == nil
                || self.frontPlayer.currentItem?.status == .failed
            if tcs != .playing || itemBroken {
                xfadeLog.notice("appDidBecomeActive: player still not playing after 1.5s (tcs=\(tcs.rawValue)) — reloading clip idx=\(self.currentQueueIndex)")
                self.loadClip(at: self.currentQueueIndex, onFront: true, startPlaying: true)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeTimeObserver()
        bufferingObservation?.invalidate()
    }

    // MARK: Section loading

    func loadSection(_ section: String?) {
        xfadeLog.notice("loadSection(\(section ?? "nil", privacy: .public)) [COMMIT] activeWas=\(self.activeSection ?? "nil", privacy: .public)")
        committedSection = section   // this is a confirmed commit
        isPreviewMode = false
        hardCancel()
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        loadClip(at: 0, onFront: true, startPlaying: true)
        playbackProgress = 0
        overlayVisible = true        // initial overlay shows immediately (no fade)
        updateMetadata(from: 0)
        preloadBack()
        startTimeObserver()
    }

    // MARK: Section preview (fired by sidebar D-pad focus, before user commits)

    /// Immediately crossfades to the first clip of `section` without committing.
    /// Call cancelPreview() to revert, or loadSection() to commit.
    func previewSection(_ section: String?) {
        xfadeLog.notice("previewSection(\(section ?? "nil", privacy: .public)) activeWas=\(self.activeSection ?? "nil", privacy: .public) committed=\(self.committedSection ?? "nil", privacy: .public) isCrossfading=\(self.isCrossfading) gen=\(self.crossfadeGeneration)")
        guard section != activeSection else {
            xfadeLog.notice("previewSection IGNORED (same as active)")
            return
        }
        isPreviewMode = true
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        startCrossfade(to: 0, duration: Self.manualDuration, isAutoFade: false)
    }

    /// Reverts to the last committed section (called when user cancels the sidebar).
    func cancelPreview() {
        xfadeLog.notice("cancelPreview active=\(self.activeSection ?? "nil", privacy: .public) committed=\(self.committedSection ?? "nil", privacy: .public)")
        guard committedSection != activeSection else {
            xfadeLog.notice("cancelPreview NO-OP (active==committed)")
            return
        }
        isPreviewMode = false
        loadSection(committedSection)
    }

    // MARK: Navigation

    func next() {
        flash(right: true)
        startCrossfade(to: (currentQueueIndex + 1) % queue.count,
                       duration: Self.manualDuration, isAutoFade: false)
    }

    func prev() {
        flash(right: false)
        startCrossfade(to: (currentQueueIndex - 1 + queue.count) % queue.count,
                       duration: Self.manualDuration, isAutoFade: false)
    }

    // MARK: Private — unified crossfade

    private func startCrossfade(to targetIdx: Int, duration: TimeInterval, isAutoFade: Bool) {
        guard !queue.isEmpty else { return }

        let targetURL      = queue[targetIdx].remoteVideoURL
        let preloadedURL   = (backPlayer.currentItem?.asset as? AVURLAsset)?.url
        let reusePreloaded = targetURL != nil && targetURL == preloadedURL

        xfadeLog.notice("startCrossfade -> idx=\(targetIdx) dur=\(duration, format: .fixed(precision: 1)) auto=\(isAutoFade) reuse=\(reusePreloaded) preview=\(self.isPreviewMode) frontA=\(self.isFrontA) genWas=\(self.crossfadeGeneration) url=\(targetURL?.lastPathComponent ?? "nil", privacy: .public)")

        // Cancel any in-progress crossfade
        crossfadeGeneration += 1
        removeTimeObserver()
        bufferingObservation?.invalidate()
        isCrossfading = false
        autoFadeArmed = false
        resetLayersCallback?()
        if !reusePreloaded {
            backPlayer.pause()
            backPlayer.replaceCurrentItem(with: nil)
        }

        let gen = crossfadeGeneration
        isCrossfading = true
        autoFadeArmed = true

        // Fade the whole overlay OUT immediately (web adds `.fade` at the
        // very start of the transition, before the new clip even buffers).
        overlayVisible = false
        // Reset the progress bar to empty now (while it's invisible). It stays
        // frozen at 0 during the crossfade — updateProgress() is suppressed
        // while isCrossfading — so it fades back in from empty for the new
        // clip rather than flashing the outgoing clip's near-full position.
        playbackProgress = 0

        if !reusePreloaded {
            guard let url = targetURL else { isCrossfading = false; return }
            backPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        }

        backPlayer.isMuted = true
        backPlayer.seek(to: .zero)
        backPlayer.play()

        // Auto-fades: pre-loaded item should already be buffering — use a short
        // 1 s timeout so high-bitrate short clips (e.g. Palma, 7 s / 52 Mbps)
        // don't freeze on their last frame waiting for the next clip to buffer.
        // Manual skips: allow up to 4 s for a cold item to buffer.
        let bufferTimeout: TimeInterval = isAutoFade ? 1.0 : 4.0

        waitUntilLikelyToKeepUp(gen: gen, maxWait: bufferTimeout) { [weak self] in
            guard let self = self, self.crossfadeGeneration == gen else {
                xfadeLog.notice("crossfade gen=\(gen) SUPERSEDED before fade (now=\(self?.crossfadeGeneration ?? -1))")
                return
            }
            xfadeLog.notice("crossfade gen=\(gen) FADE-START dur=\(duration, format: .fixed(precision: 1)) backReady=\(self.backPlayer.currentItem?.isPlaybackLikelyToKeepUp ?? false) backStatus=\(self.backPlayer.currentItem?.status.rawValue ?? -1)")
            self.crossfadeCallback?(duration)

            // Caption + minimap update at the midpoint of the crossfade —
            // matching the website: caption.textContent is set at CROSSFADE_MS/2.
            // This keeps the title in sync with the visible video blend.
            let half = duration * 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + half) { [weak self] in
                guard let self = self, self.crossfadeGeneration == gen else { return }
                self.updateMetadata(from: targetIdx)   // swap title/map while invisible
                self.overlayVisible = true             // then fade the whole overlay IN
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self = self, self.crossfadeGeneration == gen else { return }
                self.completeFade(to: targetIdx)
            }
        }
    }

    private func waitUntilLikelyToKeepUp(gen: Int, maxWait: TimeInterval,
                                          completion: @escaping () -> Void) {
        guard let item = backPlayer.currentItem else {
            xfadeLog.notice("waitUntil gen=\(gen) no-item -> fire immediately")
            completion(); return
        }
        if item.isPlaybackLikelyToKeepUp {
            xfadeLog.notice("waitUntil gen=\(gen) already-ready -> fire immediately")
            completion(); return
        }

        // Fire `completion` EXACTLY ONCE. Whichever happens first —
        // buffer-ready observation or maxWait timeout — wins; the other is
        // cancelled. Both paths run on the main queue, so a plain flag is a
        // safe latch.
        //
        // ROOT-CAUSE FIX (premature transition + stuck video on category
        // preview): previously both the observation AND the timeout could each
        // call completion() for the SAME crossfade generation. The generation
        // guard does not catch this — it's the same gen — so a settled preview
        // would spuriously re-crossfade ~maxWait later, toggling players and
        // niling items out of phase, landing on a half-prepared (frozen) layer.
        var fired = false
        var timeoutWork: DispatchWorkItem?
        let fireOnce: (String) -> Void = { [weak self] reason in
            guard !fired else { return }
            fired = true
            timeoutWork?.cancel()
            self?.bufferingObservation?.invalidate()
            xfadeLog.notice("waitUntil gen=\(gen) FIRE via \(reason, privacy: .public)")
            completion()
        }

        bufferingObservation?.invalidate()
        bufferingObservation = item.observe(\.isPlaybackLikelyToKeepUp,
                                             options: [.new]) { item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            DispatchQueue.main.async { fireOnce("observation") }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.crossfadeGeneration == gen else { return }
            xfadeLog.error("waitUntil gen=\(gen) TIMEOUT after \(maxWait, format: .fixed(precision: 1))s (item status=\(item.status.rawValue))")
            fireOnce("timeout")
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxWait, execute: work)
    }

    // ── Bug 1 fix: completeFade() calls finalizeLayersCallback AFTER toggle ──
    private func completeFade(to targetIdx: Int) {
        xfadeLog.notice("completeFade idx=\(targetIdx) frontAWas=\(self.isFrontA) -> frontA=\(!self.isFrontA)")
        frontPlayer.pause()
        frontPlayer.replaceCurrentItem(with: nil)

        isFrontA.toggle()                   // swap players
        // both players stay muted — visual-only app, audio must not interrupt AirPlay

        currentQueueIndex = targetIdx
        isCrossfading = false
        autoFadeArmed = false
        playbackProgress = 0          // restart the progress bar for the new clip

        // Finalize opacities only NOW that isFrontA is correct
        finalizeLayersCallback?()

        preloadBack()
        startTimeObserver()
    }

    // MARK: Private — hard cancel (destroys everything)

    private func hardCancel() {
        xfadeLog.notice("hardCancel frontA=\(self.isFrontA) isCrossfading=\(self.isCrossfading) genWas=\(self.crossfadeGeneration)")
        crossfadeGeneration += 1
        removeTimeObserver()
        bufferingObservation?.invalidate()
        isCrossfading = false
        autoFadeArmed = false
        backPlayer.pause()
        backPlayer.replaceCurrentItem(with: nil)
        resetLayersCallback?()
        if frontPlayer.timeControlStatus == .paused { frontPlayer.play() }
    }

    // MARK: Private — auto crossfade

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverOwner = frontPlayer
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval,
                                                           queue: .main) { [weak self] _ in
            self?.updateProgress()
            self?.checkAutoFade()
            self?.stuckWatchdog()
        }
        // Reset watchdog baseline for the new front clip.
        lastWatchdogTime = -1
        stalledTicks = 0
        loggedStuck = false
    }

    /// Detects the real "stuck video" symptom: front player should be playing
    /// (not crossfading, not preview-paused) but currentTime is not advancing.
    private func stuckWatchdog() {
        guard !isCrossfading else { lastWatchdogTime = -1; return }
        guard let item = frontPlayer.currentItem, item.status == .readyToPlay else { return }
        let now = frontPlayer.currentTime().seconds
        guard now.isFinite else { return }

        if lastWatchdogTime >= 0 {
            let advanced = now - lastWatchdogTime
            // Front player should be playing at rate 1; if it's not advancing
            // meaningfully across a tick (0.25s) it's stalled.
            if frontPlayer.rate > 0 && advanced < 0.05 {
                stalledTicks += 1
                if stalledTicks >= 4 && !loggedStuck {   // ~1s of no movement
                    loggedStuck = true
                    stuckEventCount += 1
                    xfadeLog.error("STUCK front frozen at t=\(now, format: .fixed(precision: 2)) idx=\(self.currentQueueIndex) title=\(self.currentTitle, privacy: .public) frontA=\(self.isFrontA) rate=\(self.frontPlayer.rate) tcs=\(self.frontPlayer.timeControlStatus.rawValue) reason=\(self.frontPlayer.reasonForWaitingToPlay?.rawValue ?? "nil", privacy: .public) likelyKeepUp=\(item.isPlaybackLikelyToKeepUp) bufEmpty=\(item.isPlaybackBufferEmpty)")
                }
                if stalledTicks >= 12 {  // ~3s stuck — reload the clip
                    xfadeLog.error("STUCK 3s — reloading clip idx=\(self.currentQueueIndex)")
                    stalledTicks = 0
                    loggedStuck = false
                    loadClip(at: currentQueueIndex, onFront: true, startPlaying: true)
                }
            } else if advanced >= 0.05 {
                if loggedStuck {
                    xfadeLog.notice("RECOVERED front advancing again at t=\(now, format: .fixed(precision: 2)) idx=\(self.currentQueueIndex)")
                }
                stalledTicks = 0
                loggedStuck = false
            }
        }
        lastWatchdogTime = now
    }

    private func updateProgress() {
        // Frozen during a crossfade — the bar is reset to 0 and fades back in
        // from empty when the new clip commits (see startCrossfade/completeFade).
        guard !isCrossfading else { return }
        guard let item = frontPlayer.currentItem, item.status == .readyToPlay else { return }
        let dur = item.duration.seconds
        let cur = frontPlayer.currentTime().seconds
        guard dur.isFinite, dur > 0 else { return }
        playbackProgress = min(1, max(0, cur / dur))
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let owner = timeObserverOwner {
            owner.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverOwner = nil
    }

    private func checkAutoFade() {
        guard !isPreviewMode, !autoFadeArmed, !isCrossfading,
              let item = frontPlayer.currentItem,
              item.status == .readyToPlay else { return }
        let dur = item.duration.seconds
        let elapsed = frontPlayer.currentTime().seconds
        let rem = dur - elapsed
        guard dur.isFinite, dur > 0, rem > 0 else { return }

        // Production: fire ~4 s before the clip's natural end.
        // Fast test mode: fire 3 s in with a quick 1 s fade, so the
        // auto-advance is observable in seconds for any clip length.
        let shouldFade = fastAutoFade ? (elapsed >= 3.0) : (rem <= Self.autoDuration + 0.2)
        guard shouldFade else { return }

        xfadeLog.notice("checkAutoFade TRIGGER elapsed=\(elapsed, format: .fixed(precision: 1)) dur=\(dur, format: .fixed(precision: 1)) rem=\(rem, format: .fixed(precision: 1)) idx=\(self.currentQueueIndex) preview=\(self.isPreviewMode)")
        autoFadeArmed = true
        let nextIdx = (currentQueueIndex + 1) % queue.count
        let fadeDuration = fastAutoFade ? 1.0 : Self.autoDuration
        startCrossfade(to: nextIdx, duration: fadeDuration, isAutoFade: true)
    }

    // MARK: Private — helpers

    private func loadClip(at index: Int, onFront: Bool, startPlaying: Bool) {
        guard !queue.isEmpty, index < queue.count else { return }
        let video  = queue[index]
        let player = onFront ? frontPlayer : backPlayer
        guard let url = video.remoteVideoURL else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if onFront {
            if startPlaying { player.seek(to: .zero); player.play() }
        }
    }

    private func preloadBack() {
        guard !queue.isEmpty else { return }
        let nextIdx = (currentQueueIndex + 1) % queue.count
        loadClip(at: nextIdx, onFront: false, startPlaying: false)
    }

    private func updateMetadata(from index: Int) {
        guard !queue.isEmpty, index < queue.count else { return }
        let v = queue[index]
        currentTitle = v.displayTitle
        currentLat   = v.lat
        currentLng   = v.lng
    }

    private func flash(right: Bool) {
        if right {
            rightFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in self?.rightFlash = false }
        } else {
            leftFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in self?.leftFlash = false }
        }
    }
}
