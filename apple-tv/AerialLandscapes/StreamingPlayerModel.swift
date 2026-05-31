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
    @Published private(set) var activeSection: String? = nil
    @Published private(set) var currentLat: Double? = nil
    @Published private(set) var currentLng: Double? = nil
    @Published var leftFlash  = false
    @Published var rightFlash = false

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

    static let autoDuration:   TimeInterval = 4.0
    static let manualDuration: TimeInterval = 1.5   // slightly longer for buffering headroom

    // MARK: Init

    init() {
        playerA.isMuted = false
        playerB.isMuted = true
        loadSection(nil)
    }

    deinit {
        removeTimeObserver()
        bufferingObservation?.invalidate()
    }

    // MARK: Section loading

    func loadSection(_ section: String?) {
        hardCancel()
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        loadClip(at: 0, onFront: true, startPlaying: true)
        updateMetadata(from: 0)
        preloadBack()
        startTimeObserver()
    }

    // MARK: Navigation

    func next() {
        flash(right: true)
        startCrossfade(to: (currentQueueIndex + 1) % queue.count,
                       duration: Self.manualDuration)
    }

    func prev() {
        flash(right: false)
        startCrossfade(to: (currentQueueIndex - 1 + queue.count) % queue.count,
                       duration: Self.manualDuration)
    }

    // MARK: Private — unified crossfade

    private func startCrossfade(to targetIdx: Int, duration: TimeInterval) {
        guard !queue.isEmpty else { return }

        // ── Bug 2 fix: reuse preloaded item if it's already the right URL ──
        let targetURL      = queue[targetIdx].remoteVideoURL
        let preloadedURL   = (backPlayer.currentItem?.asset as? AVURLAsset)?.url
        let reusePreloaded = targetURL != nil && targetURL == preloadedURL

        // Cancel any in-progress crossfade
        crossfadeGeneration += 1
        removeTimeObserver()
        bufferingObservation?.invalidate()
        isCrossfading = false
        autoFadeArmed = false
        resetLayersCallback?()
        frontPlayer.isMuted = false

        if !reusePreloaded {
            backPlayer.pause()
            backPlayer.replaceCurrentItem(with: nil)
        }

        let gen = crossfadeGeneration
        isCrossfading = true
        autoFadeArmed = true

        if !reusePreloaded {
            guard let url = targetURL else { isCrossfading = false; return }
            backPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        }

        // ── Bug 3 fix: caption updates NOW (as the new video starts fading in) ──
        updateMetadata(from: targetIdx)

        backPlayer.isMuted = true
        backPlayer.seek(to: .zero)
        backPlayer.play()

        // ── Wait until the back player has enough data to show a frame ────
        // Falls through after 4s if buffering is slow.
        waitUntilLikelyToKeepUp(gen: gen) { [weak self] in
            guard let self = self, self.crossfadeGeneration == gen else { return }
            self.crossfadeCallback?(duration)

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self = self, self.crossfadeGeneration == gen else { return }
                self.completeFade(to: targetIdx)
            }
        }
    }

    // Wait for isPlaybackLikelyToKeepUp; fall through after `maxWait` seconds.
    private func waitUntilLikelyToKeepUp(gen: Int, completion: @escaping () -> Void) {
        guard let item = backPlayer.currentItem else { completion(); return }
        if item.isPlaybackLikelyToKeepUp { completion(); return }

        let maxWait = 4.0
        bufferingObservation?.invalidate()
        bufferingObservation = item.observe(\.isPlaybackLikelyToKeepUp,
                                             options: [.new]) { [weak self] item, _ in
            guard item.isPlaybackLikelyToKeepUp else { return }
            self?.bufferingObservation?.invalidate()
            DispatchQueue.main.async { completion() }
        }
        // Fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + maxWait) { [weak self] in
            guard let self = self, self.crossfadeGeneration == gen else { return }
            self.bufferingObservation?.invalidate()
            completion()
        }
    }

    // ── Bug 1 fix: completeFade() calls finalizeLayersCallback AFTER toggle ──
    private func completeFade(to targetIdx: Int) {
        frontPlayer.pause()
        frontPlayer.replaceCurrentItem(with: nil)

        isFrontA.toggle()                   // swap players
        frontPlayer.isMuted = false         // new front gets audio
        backPlayer.isMuted  = true

        currentQueueIndex = targetIdx
        isCrossfading = false
        autoFadeArmed = false

        // Finalize opacities only NOW that isFrontA is correct
        finalizeLayersCallback?()

        preloadBack()
        startTimeObserver()
    }

    // MARK: Private — hard cancel (destroys everything)

    private func hardCancel() {
        crossfadeGeneration += 1
        removeTimeObserver()
        bufferingObservation?.invalidate()
        isCrossfading = false
        autoFadeArmed = false
        backPlayer.pause()
        backPlayer.replaceCurrentItem(with: nil)
        backPlayer.isMuted = true
        resetLayersCallback?()
        frontPlayer.isMuted = false
        if frontPlayer.timeControlStatus == .paused { frontPlayer.play() }
    }

    // MARK: Private — auto crossfade

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverOwner = frontPlayer
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval,
                                                           queue: .main) { [weak self] _ in
            self?.checkAutoFade()
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let owner = timeObserverOwner {
            owner.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverOwner = nil
    }

    private func checkAutoFade() {
        guard !autoFadeArmed, !isCrossfading,
              let item = frontPlayer.currentItem,
              item.status == .readyToPlay else { return }
        let dur = item.duration.seconds
        let rem = dur - frontPlayer.currentTime().seconds
        guard dur.isFinite, dur > 0, rem > 0 else { return }
        if rem <= Self.autoDuration + 0.2 {
            autoFadeArmed = true
            let nextIdx = (currentQueueIndex + 1) % queue.count
            startCrossfade(to: nextIdx, duration: Self.autoDuration)
        }
    }

    // MARK: Private — helpers

    private func loadClip(at index: Int, onFront: Bool, startPlaying: Bool) {
        guard !queue.isEmpty, index < queue.count else { return }
        let video  = queue[index]
        let player = onFront ? frontPlayer : backPlayer
        guard let url = video.remoteVideoURL else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if onFront {
            player.isMuted = false
            if startPlaying { player.seek(to: .zero); player.play() }
        } else {
            player.isMuted = true
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
