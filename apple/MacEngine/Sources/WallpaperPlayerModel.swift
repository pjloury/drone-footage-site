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

private let autoFadeDuration:   TimeInterval = 4.0   // uniform 4s fade across all platforms/triggers
private let manualFadeDuration: TimeInterval = 4.0
// Cap every clip at maxPlaySeconds so long clips don't linger. Default on.
private let limitPlayTime = true
private let maxPlaySeconds: TimeInterval = 60
// Unified buffer-readiness timeout before a crossfade proceeds anyway
// (same value on the tvOS engine).
private let bufferReadyTimeout: TimeInterval = 5.0
// Unified stall-recovery ladder — same rungs on tvOS and Mac:
// kick play() at 4s (system pause), reload the clip once at 8s,
// skip to the next clip at 12s.
private let stallKickAfter:   TimeInterval = 4
private let stallReloadAfter: TimeInterval = 8
private let stallSkipAfter:   TimeInterval = 12
private let maxConsecutiveStallSkips = 5

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
    private var kickedStall = false
    private var reloadedStall = false
    // Circuit breaker (mirrors the website's MAX_AUTO_SKIPS): after this many
    // consecutive stall-skips with no healthy playback in between, stop
    // strobing through the catalog (and hammering R2) and keep retrying the
    // current clip instead. Cleared by any healthy advancement.
    private var consecutiveStallSkips = 0
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
        // Start the moment first frames are decodable. Tried the tvOS default
        // (autowait=true) here: AVPlayer then refuses to START until keepUp,
        // which on these full-res encodes left every clip frozen at t=0 in
        // waitingToPlayAtSpecifiedRate until the 9s watchdog skipped it — a
        // strobe through the whole catalog with nothing ever playing. So keep
        // instant start, buffer deeper ahead (see loadClip), and recover from
        // the resulting non-auto-resuming dry-outs in recoverFromStall.
        playerA.automaticallyWaitsToMinimizeStalling = false
        playerB.automaticallyWaitsToMinimizeStalling = false
        observeRateChanges(playerA, tag: "A")
        observeRateChanges(playerB, tag: "B")
        // With automaticallyWaitsToMinimizeStalling=false a momentary buffer
        // dry-out stalls playback (rate silently drops to 0) and AVPlayer
        // NEVER auto-resumes — this was the dominant cause of multi-second
        // freezes (clustered around crossfades, where two players fetch and
        // decode at once). Resume immediately instead of waiting for the
        // stall watchdog's multi-second kick.
        let stallObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, !self.isUserPaused,
                  let item = note.object as? AVPlayerItem else { return }
            let player: AVPlayer
            if item === self.playerA.currentItem { player = self.playerA }
            else if item === self.playerB.currentItem { player = self.playerB }
            else { return }
            self.recoverFromStall(player, item: item)
        }
        rateObservers.append(stallObs)
        // start() is called by WallpaperWindowController after windows are ready
    }

    // Diagnostic: AVFoundation reports WHY a player's rate changed. A stall
    // where tcs flips to .paused without any pause() in this file means the
    // pause came from outside — this reveals whether it's setRateFailed
    // (decoder/resource failure), audioSessionInterrupted, appBackgrounded
    // (App Nap), or an actual setRateCalled from somewhere unexpected.
    private var rateObservers: [NSObjectProtocol] = []
    private func observeRateChanges(_ player: AVPlayer, tag: String) {
        let obs = NotificationCenter.default.addObserver(
            forName: AVPlayer.rateDidChangeNotification, object: player, queue: .main
        ) { [weak self, weak player] note in
            guard let self, let player else { return }
            let reason = note.userInfo?[AVPlayer.rateDidChangeReasonKey] as? String ?? "nil"
            let waiting = player.reasonForWaitingToPlay?.rawValue ?? "-"
            let isFront = (player === self.frontPlayer)
            WallpaperLog.shared.log("rate",
                "m\(self.mid) player\(tag)\(isFront ? "(front)" : "(back)") rate->\(player.rate) reason=\(reason) tcs=\(player.timeControlStatus.rawValue) waiting=\(waiting)")
        }
        rateObservers.append(obs)
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
        frontPlayer.playImmediately(atRate: 1.0)
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
    // Pause must stop BOTH players: a crossfade in flight has already play()ed
    // the back player, and completeFade would promote it to front — playback
    // visibly continued while isUserPaused stayed true, which permanently
    // disabled the stall watchdog. The next system pause (display sleep/lock)
    // then froze the wallpaper forever (found via lldb on a live freeze:
    // every checkStall bailed on the stale isUserPaused guard).
    private(set) var isUserPaused = false
    func pause() {
        isUserPaused = true
        playerA.pause()
        playerB.pause()
        WallpaperLog.shared.log("m\(mid)", "user pause")
        updateStatus()
    }
    func resume() {
        isUserPaused = false
        WallpaperLog.shared.log("m\(mid)", "user resume")
        frontPlayer.play()
        resetStallBaseline()
        updateStatus()
    }

    /// Called on system wake / screen unlock: macOS pauses AVPlayers while the
    /// display sleeps, and nothing un-pauses them at login. Resume the front
    /// clip in place (unless the user paused deliberately); the stall watchdog
    /// remains the fallback if playback can't actually restart.
    func systemWake() {
        guard !isUserPaused else { return }
        WallpaperLog.shared.log("m\(mid)",
            "systemWake tcs=\(frontPlayer.timeControlStatus.rawValue) video=\(currentVideo?.caption ?? "—")")
        frontPlayer.play()
        resetStallBaseline()
        updateStatus()
    }
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
        backPlayer.playImmediately(atRate: 1.0)

        // Mac always streams the full-resolution desktop encode (never the 720p
        // mobile version). If a clip can't keep up it is skipped by the stall
        // watchdog rather than degraded; known heavy clips are excluded from the
        // playlist up front (see VideoPlaylist).
        waitUntilReady(gen: gen, maxWait: bufferReadyTimeout) { [weak self] in
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
        // The incoming player's rate can silently collapse to 0 mid-fade
        // (rateDidChange reason=nil — observed while two players decode
        // concurrently during the crossfade). Without this re-play() the new
        // front starts frozen and sits there until the stall watchdog kicks
        // it ~2-6s later, on nearly every fade.
        if frontPlayer.timeControlStatus != .playing {
            WallpaperLog.shared.log("xfade", "m\(mid) new front not playing after fade (tcs=\(frontPlayer.timeControlStatus.rawValue)) — re-play()")
            frontPlayer.play()
        }
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
        kickedStall = false
        reloadedStall = false
        // consecutiveStallSkips deliberately NOT reset here — only healthy
        // playback advancement clears the breaker.
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

        // Advancing (and finite) — reset the clock and clear the breaker.
        if ready, now.isFinite, now > lastProgressTime + 0.1 {
            lastProgressTime = now
            lastProgressWall = Date()
            loggedStall = false
            kickedStall = false
            reloadedStall = false
            consecutiveStallSkips = 0
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
        // A system-imposed pause (display sleep, lock screen) is best fixed by
        // resuming the same clip in place — try one play() kick before skipping.
        if stuckFor >= stallKickAfter, !kickedStall, frontPlayer.timeControlStatus == .paused {
            kickedStall = true
            WallpaperLog.shared.log("stall", "m\(mid) kick: system-paused front, retrying play()")
            frontPlayer.play()
        }
        if stuckFor >= stallReloadAfter, !reloadedStall {
            reloadedStall = true
            WallpaperLog.shared.log("stall",
                "m\(mid) reloading stuck clip idx=\(currentIndex) video=\(currentVideo?.caption ?? "—")")
            if let video = currentVideo {
                loadClip(video, on: frontPlayer)
                frontPlayer.play()
            }
        }
        if stuckFor >= stallSkipAfter {
            if consecutiveStallSkips >= maxConsecutiveStallSkips {
                // Breaker tripped (likely a dead network): stop strobing
                // through the catalog; keep retrying this clip instead.
                WallpaperLog.shared.log("stall",
                    "m\(mid) breaker tripped (\(consecutiveStallSkips) skips) — retrying current clip idx=\(currentIndex)")
                resetStallBaseline()
                if let video = currentVideo {
                    loadClip(video, on: frontPlayer)
                    frontPlayer.play()
                }
            } else {
                consecutiveStallSkips += 1
                WallpaperLog.shared.log("stall",
                    "m\(mid) skipping stuck clip idx=\(currentIndex) video=\(currentVideo?.caption ?? "—") (skip #\(consecutiveStallSkips))")
                resetStallBaseline()
                let nextIdx = (currentIndex + 1) % queue.count
                startCrossfade(to: nextIdx, duration: manualFadeDuration)
            }
        }
    }

    private func checkAutoFade() {
        // A user pause must actually hold: without this guard an armed
        // crossfade resumed playback behind the user's back (see pause()).
        guard !autoFadeArmed, !isCrossfading, !isUserPaused,
              let item = frontPlayer.currentItem, item.status == .readyToPlay else { return }
        let dur = item.duration.seconds
        let elapsed = frontPlayer.currentTime().seconds
        guard dur.isFinite, dur > 0, elapsed > 0 else { return }
        // Universal semantic (matches web/tvOS): the fade must COMPLETE by
        // the clip's natural end so it never plays over a frozen last frame —
        // start one fade-length early. At the 60s cap the clip keeps playing
        // underneath the fade, so the cap itself is the start time there.
        // 0.25s = one observer tick of slack; no lower bound so a late tick
        // still fires.
        let effectiveDur = limitPlayTime ? min(dur, maxPlaySeconds) : dur
        let fireAt = max(1, min(effectiveDur, dur - autoFadeDuration))
        let remaining = fireAt - elapsed
        guard remaining <= 0.25 else { return }

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

    // Resume a stalled player as soon as its buffer can actually sustain
    // playback. Replaying immediately on a dry buffer just re-stalls in a
    // tight loop (observed several times per second on cold start), so wait
    // for isPlaybackLikelyToKeepUp before the single play().
    private var stallRecoveries: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private func recoverFromStall(_ player: AVPlayer, item: AVPlayerItem) {
        let key = ObjectIdentifier(player)
        guard stallRecoveries[key] == nil else { return }  // recovery already armed
        let isFront = (player === frontPlayer)
        WallpaperLog.shared.log("stall",
            "m\(mid) playbackStalled on \(isFront ? "front" : "back") — waiting for buffer to recover")
        if item.isPlaybackLikelyToKeepUp {
            player.play()
            return
        }
        stallRecoveries[key] = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self, weak player] obsItem, _ in
            guard obsItem.isPlaybackLikelyToKeepUp else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.stallRecoveries[key]?.invalidate()
                self.stallRecoveries[key] = nil
                guard let player, !self.isUserPaused,
                      player.currentItem === obsItem else { return }
                WallpaperLog.shared.log("stall", "m\(self.mid) buffer recovered — play()")
                player.play()
            }
        }
    }

    private func loadClip(_ video: DroneVideo, on player: AVPlayer) {
        let item = AVPlayerItem(url: video.desktopURL)
        // Buffer ~10s ahead so brief R2 throughput dips don't drain the
        // buffer mid-clip (0 = AVPlayer's automatic sizing, which kept the
        // window too small for these high-bitrate desktop encodes).
        item.preferredForwardBufferDuration = 10
        player.replaceCurrentItem(with: item)
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
