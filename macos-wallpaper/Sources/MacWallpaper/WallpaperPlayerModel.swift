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

    // MARK: - Crossfade engine (ported from tvOS StreamingPlayerModel)

    private func startCrossfade(to targetIdx: Int, duration: TimeInterval) {
        guard !queue.isEmpty else { return }

        crossfadeGeneration += 1
        let gen = crossfadeGeneration

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
        }
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

    private func loadClip(_ video: DroneVideo, on player: AVPlayer, useMobile: Bool = false) {
        let url = useMobile ? video.mobileURL : video.desktopURL
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
