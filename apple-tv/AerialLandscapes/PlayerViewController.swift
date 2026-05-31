//
//  PlayerViewController.swift
//  AerialLandscapes
//
//  Hosts two AVPlayerLayer instances (one per AVPlayer in StreamingPlayerModel)
//  and drives the 4-second crossfade via CALayer opacity animation.
//

import UIKit
import AVFoundation
import SwiftUI

class PlayerViewController: UIViewController {

    let model: StreamingPlayerModel

    // Two CALayer-level players for crossfade
    private var layerA: AVPlayerLayer!
    private var layerB: AVPlayerLayer!

    private var overlayController: UIHostingController<PlayerOverlayView>!

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
        setupOverlay()

        // Wire crossfade callback — called by model when back player has started
        model.crossfadeCallback = { [weak self] in
            self?.performCrossfade()
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
        layerA.frame = view.bounds
        layerA.opacity = 1.0
        view.layer.addSublayer(layerA)

        layerB = AVPlayerLayer(player: model.playerB)
        layerB.videoGravity = .resizeAspectFill
        layerB.frame = view.bounds
        layerB.opacity = 0.0
        view.layer.addSublayer(layerB)
    }

    // MARK: - Crossfade animation

    /// Called by model.crossfadeCallback when the back player is ready to fade in.
    func performCrossfade() {
        let fadingIn  = model.isFrontA ? layerB : layerA   // back → will become front
        let fadingOut = model.isFrontA ? layerA : layerB   // front → will become back

        let duration: CFTimeInterval = 4.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue   = 1.0
        fadeIn.duration  = duration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fadeIn.fillMode  = .forwards
        fadeIn.isRemovedOnCompletion = false
        fadingIn?.add(fadeIn, forKey: "crossfadeIn")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue   = 0.0
        fadeOut.duration  = duration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fadeOut.fillMode  = .forwards
        fadeOut.isRemovedOnCompletion = false
        fadingOut?.add(fadeOut, forKey: "crossfadeOut")

        CATransaction.commit()

        // After fade completes, set layer model values and remove animations
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            fadingIn?.removeAnimation(forKey: "crossfadeIn")
            fadingOut?.removeAnimation(forKey: "crossfadeOut")
            // isFrontA has already been toggled by model.completeCrossfade()
            let newFrontLayer = self.model.isFrontA ? self.layerA : self.layerB
            let newBackLayer  = self.model.isFrontA ? self.layerB : self.layerA
            newFrontLayer?.opacity = 1.0
            newBackLayer?.opacity  = 0.0
        }
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

    // MARK: - Siri Remote + simulator keyboard

    // UIKeyCommand runs before pressesBegan in the responder chain and is
    // the only reliable path for tvOS Simulator keyboard input.
    // Both methods call the same model handler so physical Apple TV remotes
    // (which use pressesBegan) and the simulator keyboard both work.

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(kLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(kRight)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow,    modifierFlags: [], action: #selector(kUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow,  modifierFlags: [], action: #selector(kDown)),
            UIKeyCommand(input: "\r",                         modifierFlags: [], action: #selector(kSelect)),
            UIKeyCommand(input: UIKeyCommand.inputEscape,     modifierFlags: [], action: #selector(kMenu)),
            UIKeyCommand(input: " ",                          modifierFlags: [], action: #selector(kPlayPause)),
        ]
    }

    @objc private func kLeft()      { _ = model.handleRemotePress(.leftArrow) }
    @objc private func kRight()     { _ = model.handleRemotePress(.rightArrow) }
    @objc private func kUp()        { _ = model.handleRemotePress(.upArrow) }
    @objc private func kDown()      { _ = model.handleRemotePress(.downArrow) }
    @objc private func kSelect()    { _ = model.handleRemotePress(.select) }
    @objc private func kMenu()      { _ = model.handleRemotePress(.menu) }
    @objc private func kPlayPause() { _ = model.handleRemotePress(.playPause) }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if model.handleRemotePress(press.type) { handled = true }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}
