// WallpaperWindowController.swift
// Manages desktop-level NSWindows + AVPlayerLayers.
//
// Critical macOS rule (from Apple docs): set view.layer = customLayer BEFORE
// setting view.wantsLayer = true, otherwise AppKit creates its own layer first
// and the custom layer may be ignored.
//
// Crossfade uses the same CABasicAnimation pattern as the tvOS PlayerViewController.

import AppKit
import AVFoundation

private struct ScreenPair {
    let window: NSWindow
    let viewA: NSView   // AVPlayerLayer(playerA) as root layer
    let viewB: NSView   // AVPlayerLayer(playerB) as root layer
}

@MainActor
final class WallpaperWindowController: NSObject {

    let model: WallpaperPlayerModel
    private var screens: [ScreenPair] = []
    private var rebuildTimer: Timer?  // debounce screen-change notifications

    // Expose model surface for status bar
    var currentVideo:    DroneVideo?  { model.currentVideo }
    var streamStatus:    StreamStatus { model.streamStatus }
    var isPlaying:       Bool         { model.isPlaying }
    var historyCount:    Int          { model.history.count }
    var onStatusChanged: (() -> Void)? {
        get { model.onStatusChanged }
        set { model.onStatusChanged = newValue }
    }

    init(model: WallpaperPlayerModel) {
        self.model = model
        super.init()
        wireCallbacks()
        buildWindows()
        model.start()
        // Register AFTER buildWindows to avoid spurious notifications during init
        DispatchQueue.main.async {
            NotificationCenter.default.addObserver(self,
                selector: #selector(self.screensChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil)
        }
    }

    func next()   { model.next() }
    func prev()   { model.prev() }
    func pause()  { model.pause() }
    func resume() { model.resume() }

    // MARK: - Window / view setup

    private func buildWindows() {
        screens.forEach { $0.window.close() }
        screens = NSScreen.screens.map { makeScreenPair(for: $0) }
        setLayerOpacities()
    }

    private func makeScreenPair(for screen: NSScreen) -> ScreenPair {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = .black

        let bounds = CGRect(origin: .zero, size: screen.frame.size)

        // Container: explicit CALayer set BEFORE wantsLayer so AppKit doesn't override it
        let container = NSView(frame: bounds)
        container.autoresizingMask = [.width, .height]
        let rootCALayer = CALayer()
        rootCALayer.backgroundColor = CGColor.black
        container.layer = rootCALayer       // BEFORE wantsLayer
        container.wantsLayer = true

        let viewA = makePlayerView(model.playerA, bounds: bounds)
        let viewB = makePlayerView(model.playerB, bounds: bounds)
        container.addSubview(viewA)
        container.addSubview(viewB)         // viewB on top in z-order

        window.contentView = container
        window.orderFront(nil)

        return ScreenPair(window: window, viewA: viewA, viewB: viewB)
    }

    private func makePlayerView(_ player: AVPlayer, bounds: CGRect) -> NSView {
        let view = NSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        // Set custom layer BEFORE wantsLayer = true (Apple docs requirement)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer = playerLayer
        view.wantsLayer = true
        return view
    }

    // MARK: - Model callbacks (same pattern as tvOS PlayerViewController)

    private func wireCallbacks() {
        model.crossfadeCallback = { [weak self] duration in
            self?.performCrossfade(duration: duration)
        }
        model.resetLayersCallback = { [weak self] in
            self?.setLayerOpacities()
        }
        // Called AFTER model.isFrontA.toggle() — reads correct post-toggle state
        model.finalizeLayersCallback = { [weak self] in
            self?.setLayerOpacities()
        }
    }

    // MARK: - Layer animation (CABasicAnimation, mirrors tvOS PlayerViewController)

    private func performCrossfade(duration: TimeInterval) {
        for pair in screens {
            // isFrontA not yet toggled: front=A(showing), back=B(new video)
            // back layer fades IN (0→1), front layer fades OUT (1→0)
            let fadingIn  = model.isFrontA ? pair.viewB.layer : pair.viewA.layer
            let fadingOut = model.isFrontA ? pair.viewA.layer : pair.viewB.layer

            let anim: (Float, Float) -> CABasicAnimation = { from, to in
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = from; a.toValue = to
                a.duration  = duration
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.fillMode = .forwards
                a.isRemovedOnCompletion = false
                return a
            }
            fadingIn?.add(anim(0, 1),  forKey: "fadeIn")
            fadingOut?.add(anim(1, 0), forKey: "fadeOut")
        }
    }

    // Snap both layers to final state. Called by both resetLayersCallback (cancel)
    // and finalizeLayersCallback (complete). model.isFrontA is already in its
    // correct final state at both call sites.
    private func setLayerOpacities() {
        for pair in screens {
            let front = model.isFrontA ? pair.viewA.layer : pair.viewB.layer
            let back  = model.isFrontA ? pair.viewB.layer : pair.viewA.layer
            front?.removeAllAnimations(); front?.opacity = 1.0
            back?.removeAllAnimations();  back?.opacity  = 0.0
        }
    }

    // Debounce screen changes — ordering a window to front at desktop level
    // can spuriously fire this notification during init.
    @objc private func screensChanged() {
        rebuildTimer?.invalidate()
        rebuildTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.buildWindows()
        }
    }
}
