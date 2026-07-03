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
// Cap every clip at maxPlaySeconds so long clips don't linger. Default on.
private let limitPlayTime = true
private let maxPlaySeconds: TimeInterval = 60
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

    // Stall-watchdog state. A stalled clip (e.g. a buffer underrun) freezes
    // forever otherwise: auto-advance only fires as currentTime nears the clip
    // end, and — critically — this MUST run on a wall-clock timer, NOT AVPlayer's
    // periodic time observer, because that observer stops firing the moment
    // playback stalls (it's tied to the advancing timeline). The old
    // observer-driven watchdog therefore never fired on a real stall.
    private var stallTimer: Timer?
    private var lastProgressTime: Double = -1
    private var lastProgressWall = Date()
    private var loggedStall = false
    private var progressLogTick = 0

    // Per-instance tag for the shared log — with one model per display, log
    // lines are useless unless we can tell which display they came from.
    private static var nextInstanceId = 0
    let mid: Int

    override init() {
        Self.nextInstanceId += 1
        mid = Self.nextInstanceId
        super.init()
        playerA.isMuted = true
        playerB.isMuted = true
        // Start playing the moment the first frames are decodable instead of
        // waiting to pre-buffer a stall-proof window. The default (true) makes
        // AVPlayer build a buffer sized for the clip's bitrate before it begins
        // — for a heavy desktop encode cold from R2 that's a multi-second to
        // ~30s black wait on first launch. We trade that for an immediate start;
        // the stall watchdog already skips a clip that can't sustain playback.
        playerA.automaticallyWaitsToMinimizeStalling = false
        playerB.automaticallyWaitsToMinimizeStalling = false
        // start() is called by WallpaperWindowController after windows are ready
    }

    func start() {
        // Start immediately from the bundled fallback so there's no launch
        // delay, then upgrade to the cloud catalog in the background. If it
        // brings new videos, reshuffle the queue so they enter rotation (the
        // currently-playing clip keeps going).
        loadInitial()
        Task { @MainActor [weak self] in
            let changed = await VideoPlaylist.load()
            guard let self, changed, !self.queue.isEmpty else { return }
            self.queue = VideoPlaylist.shuffled()
            self.currentIndex = 0
            self.preloadBack()
        }
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

    // The watchdog must ignore a pause the USER asked for, but a pause the
    // system imposed (e.g. clip ran to its end because auto-fade never armed)
    // is a freeze it must recover from — so track user intent explicitly.
    private(set) var isUserPaused = false
    func pause()  { isUserPaused = true;  frontPlayer.pause(); updateStatus() }
    func resume() { isUserPaused = false; frontPlayer.play();  updateStatus() }
    var isPlaying: Bool { frontPlayer.rate != 0 }

    /// Pause both players and stop the time observer. Used by the screensaver
    /// host when macOS calls stopAnimation() (saver dismissed / display woke).
    func suspend() {
        removeTimeObserver()
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
        WallpaperLog.shared.log("xfade", "m\(mid) START gen=\(gen) to idx=\(targetIdx) video=\(queue[targetIdx].caption) dur=\(duration) isFrontA=\(isFrontA)")

        removeTimeObserver()
        bufferingObservation?.invalidate()
        isCrossfading = false
        autoFadeArmed = false
        resetLayersCallback?()          // snap layers to clean baseline immediately

        let video = queue[targetIdx]
        loadClip(video, on: backPlayer)
        backPlayer.seek(to: .zero)
        backPlayer.play()

        // Mac always streams the full-resolution desktop encode (never the 720p
        // mobile version). If a clip can't keep up it is skipped by the stall
        // watchdog rather than degraded; known heavy clips are excluded from the
        // playlist up front (see VideoPlaylist).
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
        WallpaperLog.shared.log("xfade", "m\(mid) COMPLETE to idx=\(targetIdx) video=\(video.caption) togglingFrontA \(isFrontA)->\(!isFrontA)")
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

    // MARK: - Auto crossfade (time observer, same as tvOS)

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverOwner = frontPlayer
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateStatus()
            self?.checkAutoFade()
        }
        // Stall detection runs on its own wall-clock timer so it keeps checking
        // even when playback (and the time observer above) is frozen.
        resetStallBaseline()
        stallTimer?.invalidate()
        stallTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkStall()
        }
    }

    private func resetStallBaseline() {
        lastProgressTime = -1
        lastProgressWall = Date()
        loggedStall = false
    }

    /// Wall-clock stall check: if the front clip should be showing motion but
    /// currentTime isn't advancing, skip to the next clip. Covers every
    /// non-advancing state EXCEPT a deliberate user pause:
    ///  - buffering underrun (rate>0, time frozen)
    ///  - item that never reaches .readyToPlay (load wedged — must NOT reset
    ///    the baseline here, or the watchdog can never fire; that hole caused
    ///    a days-long freeze)
    ///  - clip ran to its end because auto-fade never armed (system pause)
    private func checkStall() {
        guard !isCrossfading else { resetStallBaseline(); return }
        guard frontPlayer.currentItem != nil else { resetStallBaseline(); return }
        guard !isUserPaused else { return }

        let item = frontPlayer.currentItem
        let ready = item?.status == .readyToPlay
        let now = frontPlayer.currentTime().seconds

        // Periodic progress trace (~30s) so the log shows per-display truth.
        progressLogTick += 1
        if progressLogTick % 30 == 1 {
            let dur = item?.duration.seconds ?? .nan
            WallpaperLog.shared.log("m\(mid)",
                "progress t=\(String(format: "%.1f", now))/\(String(format: "%.1f", dur)) video=\(currentVideo?.caption ?? "—") tcs=\(frontPlayer.timeControlStatus.rawValue) rate=\(frontPlayer.rate) ready=\(ready) keepUp=\(item?.isPlaybackLikelyToKeepUp ?? false)")
        }

        // Advancing (and finite) — reset the clock and we're healthy.
        if ready, now.isFinite, now > lastProgressTime + 0.1 {
            lastProgressTime = now
            lastProgressWall = Date()
            loggedStall = false
            return
        }

        // Not advancing (buffer-starved, never-ready, or ended): let wall-clock
        // time accumulate toward the skip.
        let stuckFor = Date().timeIntervalSince(lastProgressWall)
        if stuckFor >= 2 && !loggedStall {
            loggedStall = true
            WallpaperLog.shared.log("stall",
                "m\(mid) not advancing ~\(Int(stuckFor))s at t=\(String(format: "%.2f", now)) idx=\(currentIndex) video=\(currentVideo?.caption ?? "—") tcs=\(frontPlayer.timeControlStatus.rawValue) ready=\(ready) keepUp=\(item?.isPlaybackLikelyToKeepUp ?? false) bufEmpty=\(item?.isPlaybackBufferEmpty ?? false)")
        }
        if stuckFor >= 8 {                          // stuck 8s → skip it
            WallpaperLog.shared.log("stall",
                "m\(mid) skipping stuck clip idx=\(currentIndex) video=\(currentVideo?.caption ?? "—")")
            resetStallBaseline()
            let nextIdx = (currentIndex + 1) % queue.count
            startCrossfade(to: nextIdx, duration: manualFadeDuration)
        }
    }

    private func checkAutoFade() {
        guard !autoFadeArmed, !isCrossfading,
              let item = frontPlayer.currentItem, item.status == .readyToPlay else { return }
        let dur = item.duration.seconds
        let elapsed = frontPlayer.currentTime().seconds
        guard dur.isFinite, dur > 0, elapsed > 0 else { return }
        // Cap each clip at maxPlaySeconds when the play-time limit is on, so a
        // long clip auto-fades at the cap instead of running its full length.
        let effectiveDur = limitPlayTime ? min(dur, maxPlaySeconds) : dur
        let remaining = effectiveDur - elapsed
        guard remaining <= autoFadeDuration + 0.2, remaining > 0 else { return }

        autoFadeArmed = true
        let nextIdx = (currentIndex + 1) % queue.count
        startCrossfade(to: nextIdx, duration: autoFadeDuration)
    }

    private func removeTimeObserver() {
        stallTimer?.invalidate()
        stallTimer = nil
        if let obs = timeObserver, let owner = timeObserverOwner {
            owner.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverOwner = nil
    }

    // MARK: - Helpers

    private func loadClip(_ video: DroneVideo, on player: AVPlayer) {
        player.replaceCurrentItem(with: AVPlayerItem(url: video.desktopURL))
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
