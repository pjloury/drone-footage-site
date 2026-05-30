//
//  PlayerViewController.swift
//  AerialLandscapes
//
//  Root UIViewController: hosts AVPlayerViewController (fullscreen video)
//  and a UIHostingController (SwiftUI overlay) as child view controllers.
//  Intercepts all Siri Remote presses and routes them to StreamingPlayerModel.
//

import UIKit
import AVKit
import SwiftUI

class PlayerViewController: UIViewController {

    let model: StreamingPlayerModel

    private var avController: AVPlayerViewController!
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
        embedAVPlayer()
        embedOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var canBecomeFirstResponder: Bool { true }

    // MARK: - Child view controllers

    private func embedAVPlayer() {
        avController = AVPlayerViewController()
        avController.player = model.player
        avController.showsPlaybackControls = false
        avController.videoGravity = .resizeAspectFill

        addChild(avController)
        view.addSubview(avController.view)
        avController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avController.view.topAnchor.constraint(equalTo: view.topAnchor),
            avController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            avController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            avController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        avController.didMove(toParent: self)
    }

    private func embedOverlay() {
        let overlay = PlayerOverlayView(model: model)
        overlayController = UIHostingController(rootView: overlay)
        overlayController.view.backgroundColor = .clear
        // Overlay is input-passive — all control goes through pressesBegan
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

    // MARK: - Siri Remote

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if model.handleRemotePress(press.type) {
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}
