// WallpaperWindowController.swift
// Manages one independent wallpaper instance per display.
//
// Why per-display: an AVPlayer can only render its video into ONE AVPlayerLayer
// at a time, so a single shared player leaves every screen after the first
// blank. Each display therefore gets its OWN WallpaperPlayerModel (its own two
// players + crossfade), so every monitor shows video — each running its own
// independent shuffle. This mirrors how the screensaver runs one model per
// ScreenSaverView instance.
//
// Critical macOS rule (from Apple docs): set view.layer = customLayer BEFORE
// setting view.wantsLayer = true, otherwise AppKit creates its own layer first
// and the custom layer may be ignored.

import AppKit
import AVFoundation

/// One display's window + its own player model + crossfade layer wiring.
@MainActor
private final class WallpaperDisplay {
    let window: NSWindow
    let model = WallpaperPlayerModel()
    private let viewA: NSView   // AVPlayerLayer(model.playerA) as root layer
    private let viewB: NSView   // AVPlayerLayer(model.playerB) as root layer

    init(screen: NSScreen) {
        // NOTE: init(contentRect:...screen:) interprets contentRect RELATIVE to
        // the passed screen's origin. Passing the global screen.frame therefore
        // double-offsets every non-primary display (primary works only because
        // its origin is 0,0) — the second monitor's window landed off in space
        // and the user saw no video there. Create relative, then pin the frame
        // explicitly in global coordinates.
        window = NSWindow(contentRect: CGRect(origin: .zero, size: screen.frame.size),
                          styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.setFrame(screen.frame, display: true)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        // ARC owns this window (the controller keeps us in `displays`).
        // Programmatic NSWindows default isReleasedWhenClosed = true, so
        // teardown's close() would release it once and dropping our reference
        // would release it AGAIN — an over-release that crashes (EXC_BAD_ACCESS
        // in objc_release) on the next pool drain, e.g. when a display changes.
        window.isReleasedWhenClosed = false
        // No open/close animation: an animated close spawns an
        // _NSWindowTransformAnimation that can be over-released during the next
        // CoreAnimation transaction commit, crashing the app.
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = .black

        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        container.autoresizingMask = [.width, .height]
        let rootCALayer = CALayer()
        rootCALayer.backgroundColor = CGColor.black
        container.layer = rootCALayer       // BEFORE wantsLayer
        container.wantsLayer = true

        viewA = Self.makePlayerView(model.playerA, bounds: bounds)
        viewB = Self.makePlayerView(model.playerB, bounds: bounds)
        container.addSubview(viewA)
        container.addSubview(viewB)         // viewB on top in z-order
        window.contentView = container
        window.orderFront(nil)

        wireCallbacks()
        setLayerOpacities()
        model.start()
    }

    private static func makePlayerView(_ player: AVPlayer, bounds: CGRect) -> NSView {
        let view = NSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.layer = playerLayer            // BEFORE wantsLayer (Apple docs)
        view.wantsLayer = true
        return view
    }

    private func wireCallbacks() {
        model.crossfadeCallback = { [weak self] duration in
            self?.performCrossfade(duration: duration)
        }
        model.resetLayersCallback = { [weak self] in self?.setLayerOpacities() }
        // Called AFTER model.isFrontA.toggle() — reads correct post-toggle state.
        model.finalizeLayersCallback = { [weak self] in self?.setLayerOpacities() }
    }

    private func performCrossfade(duration: TimeInterval) {
        // isFrontA not yet toggled: front=A(showing), back=B(new video).
        let fadingIn  = model.isFrontA ? viewB.layer : viewA.layer
        let fadingOut = model.isFrontA ? viewA.layer : viewB.layer
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

    // model.isFrontA is already in its correct final state at both call sites.
    private func setLayerOpacities() {
        let front = model.isFrontA ? viewA.layer : viewB.layer
        let back  = model.isFrontA ? viewB.layer : viewA.layer
        front?.removeAllAnimations(); front?.opacity = 1.0
        back?.removeAllAnimations();  back?.opacity  = 0.0
    }

    /// Detach players from layers and strip animations BEFORE the window/views
    /// are released, so the render server's teardown can't race a live player.
    func teardown() {
        model.suspend()
        for view in [viewA, viewB] {
            if let layer = view.layer as? AVPlayerLayer {
                layer.removeAllAnimations()
                layer.player = nil
            }
        }
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }
}

@MainActor
final class WallpaperWindowController: NSObject {

    private var displays: [WallpaperDisplay] = []
    private var rebuildTimer: Timer?  // debounce screen-change notifications
    private var screenSignature = ""  // skip no-op rebuilds (spurious notifications)
    private var statusChangedHandler: (() -> Void)?

    // Menu bar reads the primary (first) display's model.
    private var primary: WallpaperPlayerModel? { displays.first?.model }
    var currentVideo: DroneVideo?  { primary?.currentVideo }
    var streamStatus: StreamStatus { primary?.streamStatus ?? .loading }
    var isPlaying:    Bool          { primary?.isPlaying ?? false }
    var historyCount: Int           { primary?.history.count ?? 0 }
    var onStatusChanged: (() -> Void)? {
        get { statusChangedHandler }
        set { statusChangedHandler = newValue; primary?.onStatusChanged = newValue }
    }

    override init() {
        super.init()
        buildWindows()
        // Register AFTER buildWindows to avoid spurious notifications during init.
        DispatchQueue.main.async {
            NotificationCenter.default.addObserver(self,
                selector: #selector(self.screensChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // Controls apply to every display (each advances its own shuffle).
    func next()   { displays.forEach { $0.model.next() } }
    func prev()   { displays.forEach { $0.model.prev() } }
    func pause()  { displays.forEach { $0.model.pause() } }
    func resume() { displays.forEach { $0.model.resume() } }

    /// A stable fingerprint of the current display layout. If unchanged, a
    /// screen-change notification is spurious (display sleep, brightness, etc.)
    /// and we must NOT tear down/rebuild windows.
    private static func currentScreenSignature() -> String {
        NSScreen.screens
            .map { "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width),\($0.frame.height)" }
            .joined(separator: "|")
    }

    private func buildWindows() {
        WallpaperLog.shared.log("windows", "buildWindows START old=\(displays.count) newScreens=\(NSScreen.screens.count)")
        teardownDisplays()
        displays = NSScreen.screens.map { WallpaperDisplay(screen: $0) }
        screenSignature = Self.currentScreenSignature()
        primary?.onStatusChanged = statusChangedHandler   // re-attach after rebuild
        WallpaperLog.shared.log("windows", "buildWindows DONE displays=\(displays.count)")
    }

    private func teardownDisplays() {
        WallpaperLog.shared.log("windows", "teardownDisplays \(displays.count)")
        displays.forEach { $0.teardown() }
        displays = []
    }

    @objc private func screensChanged() {
        WallpaperLog.shared.log("windows", "screensChanged notification — screens now \(NSScreen.screens.count), debouncing 1s")
        rebuildTimer?.invalidate()
        rebuildTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            let sig = Self.currentScreenSignature()
            guard sig != self.screenSignature else {
                WallpaperLog.shared.log("windows", "screensChanged IGNORED — layout unchanged (\(sig))")
                return
            }
            self.buildWindows()
        }
    }
}
