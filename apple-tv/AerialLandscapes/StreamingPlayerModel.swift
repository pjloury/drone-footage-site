//
//  StreamingPlayerModel.swift
//  AerialLandscapes
//
//  Two-player crossfade engine.
//  - Automatic crossfade (4 s) triggers ~4 s before natural end-of-clip.
//  - Manual crossfade (1.2 s) fires on next() / prev().
//  - crossfadeCallback carries the duration so PlayerViewController can
//    run the matching CALayer animation.
//  - Category selection is owned entirely by SidebarViewController;
//    this model only tracks activeSection and exposes loadSection().
//

import AVFoundation
import SwiftUI

class StreamingPlayerModel: ObservableObject {

    // ── Two players for crossfade ─────────────────────────────────────────
    let playerA = AVPlayer()
    let playerB = AVPlayer()

    private(set) var isFrontA = true
    var frontPlayer: AVPlayer { isFrontA ? playerA : playerB }
    var backPlayer:  AVPlayer { isFrontA ? playerB : playerA }

    // Duration parameter: 4.0 for auto end-of-clip, 1.2 for manual skip
    var crossfadeCallback: ((TimeInterval) -> Void)?

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

    // ── Internal queue ────────────────────────────────────────────────────
    private var queue: [Video] = []
    private(set) var currentQueueIndex = 0

    private var timeObserver: Any?
    private var timeObserverOwner: AVPlayer?
    private var crossfadeArmed = false

    static let autoCrossfadeDuration:   TimeInterval = 4.0
    static let manualCrossfadeDuration: TimeInterval = 1.2

    // MARK: Init

    init() {
        playerA.isMuted = false
        playerB.isMuted = true
        loadSection(nil)
    }

    deinit { removeTimeObserver() }

    // MARK: Section / queue loading

    func loadSection(_ section: String?) {
        cancelCrossfade()
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        startClip(at: 0, onFront: true, startPlaying: true)
        preloadBack()
        startTimeObserver()
    }

    // MARK: Navigation — both use the crossfade path (manual = 1.2 s)

    func next() {
        flash(right: true)
        cancelCrossfade()
        let targetIdx = (currentQueueIndex + 1) % queue.count
        triggerManualCrossfade(to: targetIdx)
    }

    func prev() {
        flash(right: false)
        cancelCrossfade()
        let targetIdx = (currentQueueIndex - 1 + queue.count) % queue.count
        triggerManualCrossfade(to: targetIdx)
    }

    // MARK: Private — clip loading

    private func startClip(at index: Int, onFront: Bool, startPlaying: Bool) {
        let video  = queue[index]
        let player = onFront ? frontPlayer : backPlayer
        guard let url = video.remoteVideoURL else { return }

        player.replaceCurrentItem(with: AVPlayerItem(url: url))

        if onFront {
            currentTitle = video.displayTitle
            currentLat   = video.lat
            currentLng   = video.lng
            player.isMuted = false
            if startPlaying { player.seek(to: .zero); player.play() }
        } else {
            player.isMuted = true
        }
    }

    private func preloadBack() {
        let nextIdx = (currentQueueIndex + 1) % queue.count
        startClip(at: nextIdx, onFront: false, startPlaying: false)
    }

    // MARK: Private — manual crossfade (← / →)

    private func triggerManualCrossfade(to targetIdx: Int) {
        guard let url = queue[targetIdx].remoteVideoURL else { return }
        backPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        backPlayer.seek(to: .zero)
        backPlayer.play()
        backPlayer.isMuted = true

        // Signal PlayerViewController to animate layers
        crossfadeCallback?(Self.manualCrossfadeDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.manualCrossfadeDuration) { [weak self] in
            guard let self = self else { return }
            self.frontPlayer.pause()
            self.frontPlayer.replaceCurrentItem(with: nil)
            self.isFrontA.toggle()
            self.frontPlayer.isMuted = false
            self.backPlayer.isMuted  = true
            self.currentQueueIndex = targetIdx
            self.currentTitle = self.queue[targetIdx].displayTitle
            self.currentLat   = self.queue[targetIdx].lat
            self.currentLng   = self.queue[targetIdx].lng
            self.preloadBack()
            self.startTimeObserver()
        }
    }

    // MARK: Private — automatic crossfade (end-of-clip)

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverOwner = frontPlayer
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.checkCrossfade()
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let owner = timeObserverOwner {
            owner.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverOwner = nil
    }

    private func checkCrossfade() {
        guard !crossfadeArmed,
              let item = frontPlayer.currentItem,
              item.status == .readyToPlay else { return }
        let duration  = item.duration.seconds
        let remaining = duration - frontPlayer.currentTime().seconds
        guard duration.isFinite, duration > 0, remaining > 0 else { return }

        if remaining <= Self.autoCrossfadeDuration + 0.2 {
            crossfadeArmed = true
            triggerAutoCrossfade()
        }
    }

    private func triggerAutoCrossfade() {
        backPlayer.seek(to: .zero)
        backPlayer.play()
        crossfadeCallback?(Self.autoCrossfadeDuration)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCrossfadeDuration) { [weak self] in
            self?.completeAutoCrossfade()
        }
    }

    private func completeAutoCrossfade() {
        frontPlayer.pause()
        frontPlayer.replaceCurrentItem(with: nil)
        isFrontA.toggle()
        frontPlayer.isMuted = false
        backPlayer.isMuted  = true
        currentQueueIndex = (currentQueueIndex + 1) % queue.count
        currentTitle = queue[currentQueueIndex].displayTitle
        currentLat   = queue[currentQueueIndex].lat
        currentLng   = queue[currentQueueIndex].lng
        crossfadeArmed = false
        preloadBack()
        startTimeObserver()
    }

    private func cancelCrossfade() {
        removeTimeObserver()
        backPlayer.pause()
        crossfadeArmed = false
    }

    // MARK: Private — arrow flash

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
