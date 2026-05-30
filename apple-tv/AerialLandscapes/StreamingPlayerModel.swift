//
//  StreamingPlayerModel.swift
//  AerialLandscapes
//
//  Manages AVQueuePlayer streaming R2 videos in shuffle or section mode.
//  UI state (@Published properties) drives PlayerOverlayView reactively.
//

import AVFoundation
import Combine
import SwiftUI

class StreamingPlayerModel: ObservableObject {

    // ── Playback ─────────────────────────────────────────────────────────────
    let player = AVQueuePlayer()
    @Published private(set) var currentTitle = ""
    @Published private(set) var activeSection: String? = nil   // nil = shuffle all

    // ── UI state (read by overlay, mutated via handleRemotePress) ────────────
    @Published var showSectionPicker = false
    @Published var pickerFocusIndex  = 0        // 0 = Shuffle All, 1-4 = sections
    @Published var showTitleCard     = true
    @Published var leftFlash         = false
    @Published var rightFlash        = false

    // ── Sections (match the website exactly) ────────────────────────────────
    static let sections: [(id: String, name: String)] = [
        ("cities",    "Cities"),
        ("coastal",   "Coastal"),
        ("mountains", "Mountains"),
        ("desert",    "Desert"),
    ]

    // ── Internal queue ───────────────────────────────────────────────────────
    private var queue: [Video] = []
    private(set) var currentQueueIndex = 0
    private var itemObservation: NSKeyValueObservation?
    private var lastKnownItem: AVPlayerItem?

    // MARK: Init

    init() {
        loadSection(nil)
    }

    // MARK: Section loading

    func loadSection(_ section: String?) {
        activeSection = section
        let pool = section == nil
            ? VideoConfig.allVideos
            : VideoConfig.allVideos.filter { $0.geozone == section }
        queue = pool.shuffled()
        currentQueueIndex = 0
        rebuildFromCurrentIndex()
    }

    // MARK: Navigation

    func next() {
        flash(right: true)
        currentQueueIndex = (currentQueueIndex + 1) % queue.count
        itemObservation?.invalidate()
        player.advanceToNextItem()
        enqueueAhead()
        currentTitle = queue.isEmpty ? "" : queue[currentQueueIndex].displayTitle
        player.play()
        startObservingItemChanges()
    }

    func prev() {
        flash(right: false)
        currentQueueIndex = (currentQueueIndex - 1 + queue.count) % queue.count
        itemObservation?.invalidate()
        rebuildFromCurrentIndex()
    }

    // MARK: Remote input

    /// Called by PlayerViewController.pressesBegan for every Siri Remote press.
    /// Returns true if the press was consumed (suppresses system handling).
    func handleRemotePress(_ type: UIPress.PressType) -> Bool {
        switch type {

        case .leftArrow:
            if showSectionPicker { showSectionPicker = false }
            else { prev() }
            return true

        case .rightArrow:
            if showSectionPicker { showSectionPicker = false }
            else { next() }
            return true

        case .upArrow:
            if showSectionPicker {
                pickerFocusIndex = max(0, pickerFocusIndex - 1)
            } else {
                showTitleCard.toggle()
            }
            return true

        case .downArrow:
            if showSectionPicker {
                pickerFocusIndex = min(Self.sections.count, pickerFocusIndex + 1)
            } else {
                showTitleCard.toggle()
            }
            return true

        case .select:
            if showSectionPicker { confirmSection() }
            return true

        case .menu:
            if showSectionPicker {
                showSectionPicker = false
                return true
            }
            return false   // Let system handle Menu when picker is closed (focuses TV menu)

        case .playPause:
            toggleSectionPicker()
            return true

        default:
            return false
        }
    }

    // MARK: Private helpers

    private func rebuildFromCurrentIndex() {
        player.removeAllItems()
        let prefetch = min(5, queue.count)
        for offset in 0..<prefetch {
            let idx = (currentQueueIndex + offset) % queue.count
            if let url = queue[idx].remoteVideoURL {
                player.insert(AVPlayerItem(url: url), after: player.items().last)
            }
        }
        currentTitle = queue.isEmpty ? "" : queue[currentQueueIndex].displayTitle
        player.play()
        startObservingItemChanges()
    }

    private func enqueueAhead() {
        let aheadIdx = (currentQueueIndex + 4) % queue.count
        if let url = queue[aheadIdx].remoteVideoURL {
            player.insert(AVPlayerItem(url: url), after: player.items().last)
        }
    }

    private func startObservingItemChanges() {
        itemObservation?.invalidate()
        lastKnownItem = player.currentItem
        itemObservation = player.observe(\.currentItem) { [weak self] player, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let newItem = player.currentItem
                guard newItem !== self.lastKnownItem, newItem != nil else { return }
                self.lastKnownItem = newItem
                self.currentQueueIndex = (self.currentQueueIndex + 1) % self.queue.count
                self.currentTitle = self.queue.isEmpty ? "" : self.queue[self.currentQueueIndex].displayTitle
                self.enqueueAhead()
            }
        }
    }

    private func toggleSectionPicker() {
        if showSectionPicker {
            showSectionPicker = false
            return
        }
        let idx = Self.sections.firstIndex(where: { $0.id == activeSection })
        pickerFocusIndex = idx.map { $0 + 1 } ?? 0
        showSectionPicker = true
    }

    private func confirmSection() {
        if pickerFocusIndex == 0 {
            loadSection(nil)
        } else {
            loadSection(Self.sections[pickerFocusIndex - 1].id)
        }
        showSectionPicker = false
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
