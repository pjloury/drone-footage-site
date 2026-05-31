//
//  StreamingPlayerModel.swift
//  AerialLandscapes
//
//  Two-player crossfade engine with a proper state machine.
//
//  Key invariants (mirrors the website's transitioning flag):
//  - Only ONE crossfade may be in-flight at a time.
//  - Calling next()/prev() while isCrossfading=true cancels the current
//    crossfade (resets layers + back player), then starts a new one.
//  - crossfadeGeneration is incremented on every cancel so stale async
//    completion blocks self-invalidate on arrival.
//  - captions and metadata update only AFTER the fade completes (the
//    front player is already showing the new clip at that point).
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

    // Callbacks set by PlayerViewController
    /// Called with the crossfade duration whenever a new fade starts.
    var crossfadeCallback: ((TimeInterval) -> Void)?
    /// Called when a crossfade is cancelled mid-flight — VC resets layer opacities.
    var resetLayersCallback: (() -> Void)?

    // ── Published state ───────────────────────────────────────────────────
    @Published private(set) var currentTitle = ""
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
    private(set) var currentQueueIndex = 0

    // ── Crossfade state machine ───────────────────────────────────────────
    private var crossfadeGeneration = 0  // invalidates stale async completions
    private var isCrossfading = false

    private var timeObserver: Any?
    private var timeObserverOwner: AVPlayer?
    private var autoFadeArmed = false   // true once auto-crossfade has been triggered

    static let autoDuration:   TimeInterval = 4.0
    static let manualDuration: TimeInterval = 1.2

    // MARK: Init

    init() {
        playerA.isMuted = false
        playerB.isMuted = true
        loadSection(nil)
    }

    deinit { removeTimeObserver() }

    // MARK: Section loading

    func loadSection(_ section: String?) {
        cancelAndReset()            // stop everything cleanly first
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        loadClip(at: 0, onFront: true, startPlaying: true)
        preloadBack()
        startTimeObserver()
        // Update caption immediately for the first clip
        updateMetadata(from: currentQueueIndex)
    }

    // MARK: Navigation

    func next() {
        flash(right: true)
        let target = (currentQueueIndex + 1) % queue.count
        startCrossfade(to: target, duration: Self.manualDuration)
    }

    func prev() {
        flash(right: false)
        let target = (currentQueueIndex - 1 + queue.count) % queue.count
        startCrossfade(to: target, duration: Self.manualDuration)
    }

    // MARK: Private — unified crossfade entry point

    private func startCrossfade(to targetIdx: Int, duration: TimeInterval) {
        // Cancel any in-progress fade first (safe to call even if not fading)
        cancelAndReset()

        guard !queue.isEmpty, let url = queue[targetIdx].remoteVideoURL else { return }

        let gen = crossfadeGeneration   // capture before any increment
        isCrossfading = true
        autoFadeArmed = true            // block auto-fade triggering during manual fade

        // Load target onto back player and start it (muted — front is still audible)
        backPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        backPlayer.seek(to: .zero)
        backPlayer.play()
        backPlayer.isMuted = true

        // Tell PlayerViewController to run the layer opacity animation
        crossfadeCallback?(duration)

        // Completion — fires only if generation hasn't been invalidated
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.crossfadeGeneration == gen else { return }
            self.completeFade(to: targetIdx)
        }
    }

    private func completeFade(to targetIdx: Int) {
        // Old front player retires — stop it and clear its item
        frontPlayer.pause()
        frontPlayer.replaceCurrentItem(with: nil)

        // Swap
        isFrontA.toggle()
        frontPlayer.isMuted = false
        backPlayer.isMuted  = true

        currentQueueIndex = targetIdx
        isCrossfading = false
        autoFadeArmed = false

        // Caption and metadata update HERE — the new clip is now fully visible
        updateMetadata(from: targetIdx)

        preloadBack()
        startTimeObserver()
    }

    // MARK: Private — hard cancel (called by next/prev/loadSection)

    private func cancelAndReset() {
        crossfadeGeneration += 1        // invalidate any pending async completion
        removeTimeObserver()
        isCrossfading = false
        autoFadeArmed = false

        // Stop back player and clear its item so it doesn't ghost
        backPlayer.pause()
        backPlayer.replaceCurrentItem(with: nil)
        backPlayer.isMuted = true

        // Tell PlayerViewController to snap layers back to clean state
        resetLayersCallback?()

        // Ensure front player is playing and audible
        frontPlayer.isMuted = false
        if frontPlayer.timeControlStatus == .paused { frontPlayer.play() }
    }

    // MARK: Private — auto crossfade (end-of-clip, time observer)

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverOwner = frontPlayer
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
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
        guard !autoFadeArmed,
              !isCrossfading,
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
        guard !queue.isEmpty else { return }
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
