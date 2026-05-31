//
//  StreamingPlayerModel.swift
//  AerialLandscapes
//
//  Manages two AVPlayers that crossfade over 4 seconds (matching the website).
//  One player is always "front" (visible), the other pre-loads the next clip.
//  When ~4 s remain in the current clip, the back player starts and crossfadeCallback
//  fires — PlayerViewController animates layer opacities.
//

import AVFoundation
import SwiftUI

class StreamingPlayerModel: ObservableObject {

    // ── Two players for crossfade ─────────────────────────────────────────
    let playerA = AVPlayer()
    let playerB = AVPlayer()

    // Which player is currently front (full opacity / audible)
    private(set) var isFrontA = true

    var frontPlayer: AVPlayer { isFrontA ? playerA : playerB }
    var backPlayer:  AVPlayer { isFrontA ? playerB : playerA }

    // Called by PlayerViewController when it should animate the crossfade
    var crossfadeCallback: (() -> Void)?

    // ── Published state ───────────────────────────────────────────────────
    @Published private(set) var currentTitle = ""
    @Published private(set) var activeSection: String? = nil
    @Published private(set) var currentLat: Double? = nil
    @Published private(set) var currentLng: Double? = nil

    @Published var showSectionPicker = false
    @Published var pickerFocusIndex  = 0
    @Published var showTitleCard     = true
    @Published var leftFlash         = false
    @Published var rightFlash        = false

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
    private var crossfadeArmed = false   // true once crossfade has been triggered for current clip

    // MARK: Init

    init() {
        playerA.isMuted = false
        playerB.isMuted = true   // back player always muted
        loadSection(nil)
    }

    deinit {
        if let obs = timeObserver { frontPlayer.removeTimeObserver(obs) }
    }

    // MARK: Section / queue loading

    func loadSection(_ section: String?) {
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        crossfadeArmed = false
        startClip(at: 0, onFront: true, startPlaying: true)
        preloadBack()
        startTimeObserver()
    }

    // MARK: Navigation

    func next() {
        flash(right: true)
        cancelCrossfade()
        currentQueueIndex = (currentQueueIndex + 1) % queue.count
        crossfadeArmed = false
        startClip(at: currentQueueIndex, onFront: true, startPlaying: true)
        preloadBack()
        startTimeObserver()
    }

    func prev() {
        flash(right: false)
        cancelCrossfade()
        currentQueueIndex = (currentQueueIndex - 1 + queue.count) % queue.count
        crossfadeArmed = false
        startClip(at: currentQueueIndex, onFront: true, startPlaying: true)
        preloadBack()
        startTimeObserver()
    }

    // MARK: Remote input

    func handleRemotePress(_ type: UIPress.PressType) -> Bool {
        switch type {
        case .leftArrow:
            if showSectionPicker { showSectionPicker = false } else { prev() }
            return true
        case .rightArrow:
            if showSectionPicker { showSectionPicker = false } else { next() }
            return true
        case .upArrow:
            if showSectionPicker {
                pickerFocusIndex = max(0, pickerFocusIndex - 1)
            } else {
                // Up opens the section picker (mirrors website's section button in top-right)
                toggleSectionPicker()
            }
            return true
        case .downArrow:
            if showSectionPicker {
                pickerFocusIndex = min(Self.sections.count, pickerFocusIndex + 1)
            }
            // Down does nothing when picker is closed — caption is always visible
            return true
        case .select:
            if showSectionPicker { confirmSection() }
            return true
        case .menu:
            if showSectionPicker { showSectionPicker = false; return true }
            return false
        case .playPause:
            toggleSectionPicker()
            return true
        default:
            return false
        }
    }

    // MARK: Private — clip loading

    private func startClip(at index: Int, onFront: Bool, startPlaying: Bool) {
        let video = queue[index]
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

    // MARK: Private — time observer + crossfade trigger

    private func startTimeObserver() {
        if let obs = timeObserver { frontPlayer.removeTimeObserver(obs) }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = frontPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.checkCrossfade()
        }
    }

    private func checkCrossfade() {
        guard !crossfadeArmed,
              let item = frontPlayer.currentItem,
              item.status == .readyToPlay else { return }
        let duration  = item.duration.seconds
        let remaining = duration - frontPlayer.currentTime().seconds
        guard duration.isFinite, duration > 0, remaining > 0 else { return }

        if remaining <= 4.2 {
            crossfadeArmed = true
            triggerCrossfade()
        }
    }

    private func triggerCrossfade() {
        // Start back player (pre-loaded clip) slightly ahead of the visual fade
        backPlayer.seek(to: .zero)
        backPlayer.play()

        // Tell PlayerViewController to animate the two layers
        crossfadeCallback?()

        // After 4 s the fade is complete — swap front/back tracking
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.completeCrossfade()
        }
    }

    private func completeCrossfade() {
        // Old front player stops (it's now behind the new clip)
        frontPlayer.pause()
        frontPlayer.replaceCurrentItem(with: nil)

        // Swap which player is "front"
        isFrontA.toggle()
        frontPlayer.isMuted = false
        backPlayer.isMuted  = true

        // Advance queue index
        currentQueueIndex = (currentQueueIndex + 1) % queue.count
        currentTitle = queue[currentQueueIndex].displayTitle
        currentLat   = queue[currentQueueIndex].lat
        currentLng   = queue[currentQueueIndex].lng
        crossfadeArmed = false

        // Pre-load the clip after this one
        preloadBack()
        startTimeObserver()
    }

    private func cancelCrossfade() {
        if let obs = timeObserver { frontPlayer.removeTimeObserver(obs); timeObserver = nil }
        backPlayer.pause()
        crossfadeArmed = false
    }

    // MARK: Private — section picker

    private func toggleSectionPicker() {
        if showSectionPicker { showSectionPicker = false; return }
        let idx = Self.sections.firstIndex(where: { $0.id == activeSection })
        pickerFocusIndex = idx.map { $0 + 1 } ?? 0
        showSectionPicker = true
    }

    private func confirmSection() {
        if pickerFocusIndex == 0 { loadSection(nil) }
        else { loadSection(Self.sections[pickerFocusIndex - 1].id) }
        showSectionPicker = false
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
