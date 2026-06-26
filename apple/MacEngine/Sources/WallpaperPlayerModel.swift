// WallpaperPlayerModel.swift
// Ports the tvOS StreamingPlayerModel crossfade engine to macOS.
// Key design points (same as tvOS):
//  - isPlaybackLikelyToKeepUp is the buffer-ready signal (not isReadyForDisplay)
//  - waitUntilReady fires exactly once via a `fired` flag (prevents double-fire)
//  - completeFade() is driven by asyncAfter, not CATransaction completion
//  - resetLayersCallback snaps layers to clean state on every new crossfade
//  - finalizeLayersCallback is called AFTER isFrontA.toggle() so VC reads correct state

import AVFoundation
import Foundation

private let autoFadeDuration:   TimeInterval = 5.0
private let manualFadeDuration: TimeInterval = 2.0
private let desktopFallbackDelay: TimeInterval = 5.0

enum StreamStatus: Equatable {
    case loading, playing, paused, buffering
    var label: String {
        switch self {
        case .loading:   return "Loading…"
        case .playing:   return "Playing"
        case .paused:    return "Paused"
        case .buffering: return "Buffering…"
        }
    }
}

@MainActor
final class WallpaperPlayerModel: NSObject {

    // MARK: - Two players
    let playerA = AVPlayer()
    let playerB = AVPlayer()
    private(set) var isFrontA = true
    var frontPlayer: AVPlayer { isFrontA ? playerA : playerB }
    var backPlayer:  AVPlayer { isFrontA ? playerB : playerA }

    // MARK: - Callbacks (set by WallpaperWindowController)
    var crossfadeCallback:     ((TimeInterval) -> Void)?
    var resetLayersCallback:   (() -> Void)?
    var finalizeLayersCallback:(() -> Void)?

    // MARK: - Published state
    private(set) var currentVideo: DroneVideo?
    private(set) var currentIndex = 0
    private(set) var streamStatus: StreamStatus = .loading
    var onStatusChanged: (() -> Void)?

    // MARK: - Playlist / history
    private var queue:   [DroneVideo] = VideoPlaylist.shuffled()
    private(set) var history: [DroneVideo] = []

    // MARK: - Crossfade state (mirrors tvOS)
    private var crossfadeGeneration = 0
    private var isCrossfading  = false
    private var autoFadeArmed  = false
    private var bufferingObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var timeObserverOwner: AVPlayer?

    // Mobile-fallback state
    private var fallbackTimer: Timer?
    private var loadingVideoForMobile: DroneVideo?

    // Stall-watchdog state. Auto-advance is driven by currentTime approaching
    // the clip end, so a frozen currentTime would otherwise NEVER advance —
    // a stalled clip (e.g. a heavy high-bitrate desktop file underbuffering)
    // freezes forever. This detects no-progress and skips to the next clip.
    private var lastWatchdogTime: Double = -1
    private var stalledTicks = 0
    private var loggedStall = false

    override init() {
        super.init()
        playerA.isMuted = true
        playerB.isMuted = true
        // start() is called by WallpaperWindowController after windows are ready
    }

    func start() {
        loadInitial()
    }


    // MARK: - Initial load

    private func loadInitial() {
        guard !queue.isEmpty else { return }
        let video = queue[0]
        currentIndex = 0
        currentVideo = video
        loadClip(video, on: frontPlayer)
        frontPlayer.play()
        updateStatus()
        preloadBack()
        startTimeObserver()
    }

    // MARK: - Navigation

    func next() {
        let idx = (currentIndex + 1) % queue.count
        startCrossfade(to: idx, duration: manualFadeDuration)
    }

    func prev() {
        guard let prev = history.popLast() else { return }
        // Find or insert the previous video at the front of the queue
        let idx: Int
        if let found = queue.firstIndex(where: { $0.id == prev.id }) {
            idx = found
        } else {
            queue.insert(prev, at: 0)
            currentIndex = max(1, currentIndex)
            idx = 0
        }
        startCrossfade(to: idx, duration: manualFadeDuration)
    }

    func pause()  { frontPlayer.pause(); updateStatus() }
    func resume() { frontPlayer.play();  updateStatus() }
    var isPlaying: Bool { frontPlayer.rate != 0 }

    /// Pause both players and stop the time observer. Used by the screensaver
    /// host when macOS calls stopAnimation() (saver dismissed / display woke).
    func suspend() {
        removeTimeObserver()
        fallbackTimer?.invalidate()
        bufferingObservation?.invalidate()
        playerA.pause()
        playerB.pause()
        updateStatus()
    }

    // MARK: - Crossfade engine (ported from tvOS StreamingPlayerModel)

    private func startCrossfade(to targetIdx: Int, duration: TimeInterval) {
        guard !queue.isEmpty else { return }

        crossfadeGeneration += 1
        let gen = crossfadeGeneration
        WallpaperLog.shared.log("xfade", "START gen=\(gen) to idx=\(targetIdx) video=\(queue[targetIdx].caption) dur=\(duration) isFrontA=\(isFrontA)")

        removeTimeObserver()
        bufferingObservation?.invalidate()
        fallbackTimer?.invalidate()
        isCrossfading = false
        autoFadeArmed = false
        resetLayersCallback?()          // snap layers to clean baseline immediately

        let video = queue[targetIdx]
        loadClip(video, on: backPlayer, useMobile: false)
        backPlayer.seek(to: .zero)
        backPlayer.play()

        // Start mobile fallback timer for slow connections
        startMobileFallback(for: video, gen: gen)

        waitUntilReady(gen: gen, maxWait: desktopFallbackDelay + 2) { [weak self] in
            guard let self, self.crossfadeGeneration == gen else { return }
            self.isCrossfading = true
            self.crossfadeCallback?(duration)

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.crossfadeGeneration == gen else { return }
                self.completeFade(to: targetIdx, video: video)
            }
        }
    }

    private func completeFade(to targetIdx: Int, video: DroneVideo) {
        WallpaperLog.shared.log("xfade", "COMPLETE to idx=\(targetIdx) video=\(video.caption) togglingFrontA \(isFrontA)->\(!isFrontA)")
        frontPlayer.pause()
        frontPlayer.replaceCurrentItem(with: nil)

        isFrontA.toggle()
        currentIndex = targetIdx
        if let prev = currentVideo { history.append(prev); if history.count > 50 { history.removeFirst() } }
        currentVideo = video
        isCrossfading = false
        autoFadeArmed = false

        finalizeLayersCallback?()       // called AFTER isFrontA.toggle()

        updateStatus()
        preloadBack()
        startTimeObserver()
    }

    // MARK: - waitUntilReady (fires exactly once — same pattern as tvOS)

    private func waitUntilReady(gen: Int, maxWait: TimeInterval, completion: @escaping () -> Void) {
        guard let item = backPlayer.currentItem else { completion(); return }
        if item.isPlaybackLikelyToKeepUp { completion(); return }

        var fired = false
        var timeoutWork: DispatchWorkItem?
        let fireOnce: () -> Void = { [weak self] in
            guard !fired else { return }
            fired = true
            timeoutWork?.cancel()
            self?.bufferingObservation?.invalidate()
            completion()
        }

        bufferingObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: .new) { item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            DispatchQueue.main.async { fireOnce() }
        }

        let work = DispatchWorkItem { fireOnce() }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxWait, execute: work)
    }

    // MARK: - Mobile fallback

    private func startMobileFallback(for video: DroneVideo, gen: Int) {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: desktopFallbackDelay, repeats: false) { [weak self] _ in
            guard let self, self.crossfadeGeneration == gen else { return }
            guard let item = self.backPlayer.currentItem, !item.isPlaybackLikelyToKeepUp else { return }
            // Desktop URL is stalling — switch to mobile
            WallpaperLog.shared.log("xfade", "MOBILE FALLBACK gen=\(gen) video=\(video.caption) — desktop stalled \(desktopFallbackDelay)s")
            self.bufferingObservation?.invalidate()
            self.loadClip(video, on: self.backPlayer, useMobile: true)
            self.backPlayer.seek(to: .zero)
            self.backPlayer.play()
            // Let waitUntilReady's timeout handle the rest from here
        }
    }

    // MARK: - Auto crossfade (time observer, same as tvOS)

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverOwner = frontPlayer
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateStatus()
            self?.checkAutoFade()
            self?.stallWatchdog()
        }
        // Reset the watchdog baseline for the newly-front clip.
        lastWatchdogTime = -1
        stalledTicks = 0
        loggedStall = false
    }

    /// Detect a frozen front clip (playing, but currentTime not advancing) and
    /// skip past it. Without this a stalled heavy clip freezes indefinitely,
    /// because auto-advance only fires as currentTime nears the clip end.
    private func stallWatchdog() {
        guard !isCrossfading else { lastWatchdogTime = -1; stalledTicks = 0; return }
        guard let item = frontPlayer.currentItem, item.status == .readyToPlay else { return }
        let now = frontPlayer.currentTime().seconds
        guard now.isFinite else { return }

        if lastWatchdogTime >= 0 {
            let advanced = now - lastWatchdogTime
            // We want it playing (rate > 0) but currentTime isn't moving.
            if frontPlayer.rate > 0 && advanced < 0.05 {
                stalledTicks += 1
                if stalledTicks == 4 && !loggedStall {   // ~1s
                    loggedStall = true
                    WallpaperLog.shared.log("stall",
                        "front frozen at t=\(String(format: "%.2f", now)) idx=\(currentIndex) video=\(currentVideo?.caption ?? "—") tcs=\(frontPlayer.timeControlStatus.rawValue) keepUp=\(item.isPlaybackLikelyToKeepUp) bufEmpty=\(item.isPlaybackBufferEmpty)")
                }
                if stalledTicks >= 16 {                  // ~4s stuck → skip it
                    WallpaperLog.shared.log("stall",
                        "skipping frozen clip idx=\(currentIndex) video=\(currentVideo?.caption ?? "—")")
                    stalledTicks = 0
                    loggedStall = false
                    let nextIdx = (currentIndex + 1) % queue.count
                    startCrossfade(to: nextIdx, duration: manualFadeDuration)
                    return
                }
            } else if advanced >= 0.05 {
                stalledTicks = 0
                loggedStall = false
            }
        }
        lastWatchdogTime = now
    }

    private func checkAutoFade() {
        guard !autoFadeArmed, !isCrossfading,
              let item = frontPlayer.currentItem, item.status == .readyToPlay else { return }
        let dur = item.duration.seconds
        let elapsed = frontPlayer.currentTime().seconds
        guard dur.isFinite, dur > 0, elapsed > 0 else { return }
        let remaining = dur - elapsed
        guard remaining <= autoFadeDuration + 0.2, remaining > 0 else { return }

        autoFadeArmed = true
        let nextIdx = (currentIndex + 1) % queue.count
        startCrossfade(to: nextIdx, duration: autoFadeDuration)
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let owner = timeObserverOwner {
            owner.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverOwner = nil
    }

    // MARK: - Helpers

    // Clips whose desktop encodes are so high-bitrate (≥40 Mbps avg, up to
    // 130) that they underbuffer and stall when streamed — see the Tier-1 list
    // in CLAUDE.md. Until they're re-encoded we stream the rock-solid 720p
    // mobile version: smooth ambient playback beats a frozen 4K frame. The
    // stall watchdog still covers any other clip that stalls unexpectedly.
    private static let heavyDesktopIDs: Set<Int> = [18, 19, 22, 30, 32, 37, 50, 62]

    private func loadClip(_ video: DroneVideo, on player: AVPlayer, useMobile: Bool = false) {
        let mobile = useMobile || Self.heavyDesktopIDs.contains(video.id)
        let url = mobile ? video.mobileURL : video.desktopURL
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = true
    }

    private func preloadBack() {
        guard !queue.isEmpty else { return }
        let nextIdx = (currentIndex + 1) % queue.count
        loadClip(queue[nextIdx], on: backPlayer)
    }

    private func updateStatus() {
        let new: StreamStatus
        switch frontPlayer.timeControlStatus {
        case .paused:                       new = .paused
        case .playing:                      new = .playing
        case .waitingToPlayAtSpecifiedRate: new = .buffering
        @unknown default:                   new = .loading
        }
        if new != streamStatus { streamStatus = new; onStatusChanged?() }
    }
}
