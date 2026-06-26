// AerialScreenSaverView.swift
// macOS screensaver host for the streaming aerial footage engine.
//
// This is the screensaver analogue of WallpaperWindowController: instead of
// desktop-level NSWindows it lives inside a single ScreenSaverView that macOS
// instantiates (one per display). It reuses the SAME WallpaperPlayerModel
// crossfade engine, streaming directly from videos.pjloury.com — no
// pre-download. The legacyScreenSaver host sandbox grants
// com.apple.security.network.client, so streaming works.
//
// Each display gets its own view → its own model → its own pair of AVPlayers.
// That independence is deliberate: it sidesteps the shared-player teardown
// hazards we hit in the wallpaper app, and lets each screen run its own
// shuffle.
//
// Cold-start: a stream needs ~0.5–2s to buffer, during which an AVPlayerLayer
// shows nothing. A poster image sits BEHIND both player layers so the very
// first frame the user sees is the clip's poster, not black; the video covers
// it as soon as the first frame decodes.

import ScreenSaver
import AVFoundation
import QuartzCore

@objc(AerialScreenSaverView)
final class AerialScreenSaverView: ScreenSaverView {

    private let model = WallpaperPlayerModel()
    private var layerA = AVPlayerLayer()
    private var layerB = AVPlayerLayer()
    private let posterLayer = CALayer()
    private let captionLayer = CATextLayer()
    private var didStart = false

    private static let captionFadeDuration: TimeInterval = 0.6

    // MARK: Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        WallpaperLog.shared.log("saver", "init frame=\(Int(bounds.width))x\(Int(bounds.height)) preview=\(isPreview)")
        wantsLayer = true
        let root = layer ?? CALayer()
        root.backgroundColor = CGColor.black
        layer = root
        layerUsesCoreImageFilters = false

        // Poster sits at the back; player layers paint over it once decoded.
        posterLayer.frame = bounds
        posterLayer.contentsGravity = .resizeAspectFill
        posterLayer.backgroundColor = CGColor.black
        root.addSublayer(posterLayer)

        layerA = AVPlayerLayer(player: model.playerA)
        layerB = AVPlayerLayer(player: model.playerB)
        for l in [layerA, layerB] {
            l.frame = bounds
            l.videoGravity = .resizeAspectFill
            root.addSublayer(l)
        }
        setLayerOpacities()

        // Caption sits on top of everything, bottom-left, like the tvOS app.
        configureCaption(on: root)
        wireCallbacks()

        // We don't draw frames ourselves — AVPlayer does. Keep the timer slow.
        animationTimeInterval = 1.0 / 5.0
    }

    // MARK: Caption (bottom-left, drop shadow — mirrors tvOS PlayerOverlayView)

    private func configureCaption(on root: CALayer) {
        captionLayer.alignmentMode = .left
        captionLayer.truncationMode = .end
        captionLayer.isWrapped = false
        captionLayer.foregroundColor = NSColor.white.cgColor
        captionLayer.opacity = 0   // fades in once the first clip is known
        // A single soft drop shadow approximates the tvOS stacked shadows so the
        // title floats clearly over any footage. (Negative y casts downward in
        // CoreAnimation's default non-flipped layer geometry.)
        captionLayer.shadowColor = NSColor.black.cgColor
        captionLayer.shadowOpacity = 0.9
        captionLayer.shadowRadius = 6
        captionLayer.shadowOffset = CGSize(width: 0, height: -2)
        root.addSublayer(captionLayer)
        layoutCaption()
    }

    private func layoutCaption() {
        // Scale with the display: ~3.3% of height, clamped to a sensible range.
        let fontSize = min(64, max(20, bounds.height * 0.033))
        let leftPad   = max(40, bounds.width  * 0.045)
        let bottomPad = max(28, bounds.height * 0.060)
        captionLayer.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        captionLayer.fontSize = fontSize
        captionLayer.contentsScale = window?.backingScaleFactor ?? 2
        captionLayer.frame = CGRect(x: leftPad, y: bottomPad,
                                    width: bounds.width - leftPad * 2,
                                    height: fontSize * 1.4)
    }

    private func updateCaption(_ text: String?, fadeIn: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        captionLayer.string = text ?? ""
        CATransaction.commit()
        if fadeIn { fadeCaption(to: 1) }
    }

    private func fadeCaption(to opacity: Float) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = captionLayer.presentation()?.opacity ?? captionLayer.opacity
        a.toValue = opacity
        a.duration = Self.captionFadeDuration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        captionLayer.add(a, forKey: "captionFade")
        captionLayer.opacity = opacity
    }

    // MARK: ScreenSaver lifecycle

    override func startAnimation() {
        super.startAnimation()
        guard !didStart else { return }
        didStart = true
        WallpaperLog.shared.log("saver", "startAnimation")
        model.start()
        loadPoster(for: model.currentVideo)
        updateCaption(model.currentVideo?.caption, fadeIn: true)
    }

    override func stopAnimation() {
        super.stopAnimation()
        WallpaperLog.shared.log("saver", "stopAnimation")
        model.suspend()
    }

    // ScreenSaverView calls this on its timer; the player drives itself so
    // there's nothing to draw, but we keep the override for correctness.
    override func animateOneFrame() {}

    override func layout() {
        super.layout()
        // Keep all sublayers full-bleed when the host resizes us.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        posterLayer.frame = bounds
        layerA.frame = bounds
        layerB.frame = bounds
        layoutCaption()
        CATransaction.commit()
    }

    // MARK: Poster (anti-black-flash for the first clip)

    private func loadPoster(for video: DroneVideo?) {
        guard let video else { return }
        let url = video.posterURL
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.posterLayer.contents = cg
                CATransaction.commit()
            }
        }.resume()
    }

    // MARK: Crossfade wiring (mirror of WallpaperWindowController)

    private func wireCallbacks() {
        model.crossfadeCallback = { [weak self] duration in
            self?.performCrossfade(duration: duration)
            // Fade the old caption out as the crossfade begins (matches website
            // / tvOS behaviour); the new title fades in when the fade completes.
            self?.fadeCaption(to: 0)
        }
        model.resetLayersCallback = { [weak self] in
            self?.setLayerOpacities()
        }
        model.finalizeLayersCallback = { [weak self] in
            guard let self else { return }
            self.setLayerOpacities()
            self.updateCaption(self.model.currentVideo?.caption, fadeIn: true)
        }
    }

    private func performCrossfade(duration: TimeInterval) {
        // isFrontA not yet toggled: front shows, back holds the new clip.
        let fadingIn  = model.isFrontA ? layerB : layerA
        let fadingOut = model.isFrontA ? layerA : layerB

        let anim: (Float, Float) -> CABasicAnimation = { from, to in
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = from; a.toValue = to
            a.duration  = duration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            return a
        }
        fadingIn.add(anim(0, 1),  forKey: "fadeIn")
        fadingOut.add(anim(1, 0), forKey: "fadeOut")
    }

    private func setLayerOpacities() {
        let front = model.isFrontA ? layerA : layerB
        let back  = model.isFrontA ? layerB : layerA
        front.removeAllAnimations(); front.opacity = 1.0
        back.removeAllAnimations();  back.opacity  = 0.0
    }

    // Screensavers have a configure sheet button; we have nothing to configure.
    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
