//
//  PlayerViewController.swift
//  AerialLandscapes
//
//  Root UIViewController:
//  - Two AVPlayerLayers for 4-second automatic crossfade (end-of-clip)
//    and 1.2-second manual crossfade (← / → skip)
//  - SidebarViewController child for category selection (slides in from left)
//  - UIKeyCommand for tvOS Simulator; pressesBegan for physical remote
//

import UIKit
import AVFoundation
import SwiftUI

// MARK: - PlayerViewController

class PlayerViewController: UIViewController {

    let model: StreamingPlayerModel

    // Two layers — one per AVPlayer — for crossfade via CALayer opacity
    private var layerA: AVPlayerLayer!
    private var layerB: AVPlayerLayer!

    // SwiftUI overlay (arrows, caption, section badge, minimap)
    private var overlayController: UIHostingController<PlayerOverlayView>!

    // Sidebar
    private var sidebarVC: SidebarViewController!
    private var dimView: UIView!
    private var sidebarVisible = false
    private static let sidebarWidth: CGFloat = 380

    // Debounce — UIKeyCommand and pressesBegan can both fire for the same
    // physical remote press; the 80 ms window collapses duplicates.
    private var lastActionAt: CFTimeInterval = 0
    private func debounced(_ action: () -> Void) {
        let now = CACurrentMediaTime()
        guard now - lastActionAt > 0.08 else { return }
        lastActionAt = now
        action()
    }

    init(model: StreamingPlayerModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupVideoLayers()
        setupDimView()
        setupSidebar()
        setupOverlay()

        model.crossfadeCallback = { [weak self] duration in
            self?.performCrossfade(duration: duration)
        }

        // Cancel: snap layers to known baseline (front=1, back=0)
        model.resetLayersCallback = { [weak self] in
            self?.setLayerOpacities()
        }

        // Finalize: called after isFrontA.toggle() — MUST read new state
        model.finalizeLayersCallback = { [weak self] in
            self?.setLayerOpacities()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layerA.frame = view.bounds
        layerB.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    // MARK: - Video layers

    private func setupVideoLayers() {
        layerA = AVPlayerLayer(player: model.playerA)
        layerA.videoGravity = .resizeAspectFill
        layerA.opacity = 1.0
        view.layer.addSublayer(layerA)

        layerB = AVPlayerLayer(player: model.playerB)
        layerB.videoGravity = .resizeAspectFill
        layerB.opacity = 0.0
        view.layer.addSublayer(layerB)
    }

    // MARK: - Crossfade animation
    //
    // Called by StreamingPlayerModel.crossfadeCallback with a duration:
    //   4.0 s — automatic end-of-clip crossfade
    //   1.2 s — manual ← / → skip

    // Bug 1 fix: no asyncAfter cleanup here.
    // Cleanup is now driven by finalizeLayersCallback which fires inside
    // completeFade() AFTER isFrontA has been toggled — so setLayerOpacities()
    // always reads the correct (post-toggle) front/back assignment.
    func performCrossfade(duration: TimeInterval) {
        let fadingIn  = model.isFrontA ? layerB : layerA   // back layer
        let fadingOut = model.isFrontA ? layerA : layerB   // front layer

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let makeAnim: (Float, Float) -> CABasicAnimation = { from, to in
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = from; a.toValue = to
            a.duration  = duration
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.fillMode = .forwards; a.isRemovedOnCompletion = false
            return a
        }
        fadingIn?.add(makeAnim(0, 1),  forKey: "fadeIn")
        fadingOut?.add(makeAnim(1, 0), forKey: "fadeOut")
        CATransaction.commit()
    }

    // Called by both resetLayersCallback (cancel) and finalizeLayersCallback (complete).
    // Reads model.isFrontA which is already in its final state at both call sites.
    private func setLayerOpacities() {
        let front = model.isFrontA ? layerA : layerB
        let back  = model.isFrontA ? layerB : layerA
        front?.removeAllAnimations()
        back?.removeAllAnimations()
        front?.opacity = 1.0
        back?.opacity  = 0.0
    }

    // MARK: - Dim view (behind sidebar, over video)

    private func setupDimView() {
        dimView = UIView()
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        dimView.alpha = 0
        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimView)
    }

    // MARK: - Sidebar

    private func setupSidebar() {
        sidebarVC = SidebarViewController()
        sidebarVC.model   = model
        sidebarVC.onClose = { [weak self] in self?.closeSidebar() }

        addChild(sidebarVC)
        let w = Self.sidebarWidth
        sidebarVC.view.frame = CGRect(x: -w, y: 0, width: w, height: view.bounds.height)
        sidebarVC.view.autoresizingMask = [.flexibleHeight]
        view.addSubview(sidebarVC.view)
        sidebarVC.didMove(toParent: self)
    }

    func openSidebar() {
        guard !sidebarVisible else { return }
        sidebarVisible = true

        UIView.animate(withDuration: 0.42, delay: 0,
                       usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                       options: .curveEaseOut) {
            self.sidebarVC.view.frame.origin.x = 0
            self.dimView.alpha = 1
        }

        // Hand focus to the sidebar table view
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    func closeSidebar() {
        guard sidebarVisible else { return }
        sidebarVisible = false

        UIView.animate(withDuration: 0.32, delay: 0,
                       usingSpringWithDamping: 0.92, initialSpringVelocity: 0,
                       options: .curveEaseIn) {
            self.sidebarVC.view.frame.origin.x = -Self.sidebarWidth
            self.dimView.alpha = 0
        }

        // Return focus to PlayerViewController
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        becomeFirstResponder()
    }

    // Route focus into the sidebar when it's open; nowhere specific when closed
    // (PlayerViewController handles everything via key commands / pressesBegan)
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        sidebarVisible ? [sidebarVC] : []
    }

    // MARK: - SwiftUI overlay

    private func setupOverlay() {
        let overlay = PlayerOverlayView(model: model)
        overlayController = UIHostingController(rootView: overlay)
        overlayController.view.backgroundColor = .clear
        overlayController.view.isUserInteractionEnabled = false

        addChild(overlayController)
        view.addSubview(overlayController.view)
        overlayController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayController.view.topAnchor.constraint(equalTo: view.topAnchor),
            overlayController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        overlayController.didMove(toParent: self)
    }

    // MARK: - Input (UIKeyCommand + pressesBegan)
    //
    // UIKeyCommand fires for simulator keyboard; pressesBegan fires for the
    // physical Siri Remote. Both call the same private action methods.
    // The 80 ms debounce in `debounced` prevents double-execution.

    // When the sidebar is open: expose only Escape (to close it) and let the
    // tvOS focus engine drive Up/Down/Select inside the table view.
    override var keyCommands: [UIKeyCommand]? {
        if sidebarVisible {
            return [
                UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(kClose)),
            ]
        }
        return [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(kLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(kRight)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow,    modifierFlags: [], action: #selector(kOpen)),
            UIKeyCommand(input: " ",                          modifierFlags: [], action: #selector(kOpen)),
        ]
    }

    @objc private func kLeft()  { debounced { self.model.prev() } }
    @objc private func kRight() { debounced { self.model.next() } }
    @objc private func kOpen()  { debounced { self.openSidebar() } }
    @objc private func kClose() { debounced { self.closeSidebar() } }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if sidebarVisible {
            for press in presses where press.type == .menu { closeSidebar(); return }
            super.pressesBegan(presses, with: event)
            return
        }
        for press in presses {
            switch press.type {
            case .leftArrow:            debounced { self.model.prev() }
            case .rightArrow:           debounced { self.model.next() }
            case .upArrow, .playPause:  debounced { self.openSidebar() }
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}
