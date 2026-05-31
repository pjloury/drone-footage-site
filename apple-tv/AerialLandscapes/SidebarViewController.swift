//
//  SidebarViewController.swift
//  AerialLandscapes
//
//  Native tvOS slide-in sidebar for category selection.
//  Uses UITableView so the system focus engine drives D-pad navigation,
//  focus rings, and cell-scale animations automatically.
//

import UIKit

// MARK: - SidebarViewController

class SidebarViewController: UIViewController {

    weak var model: StreamingPlayerModel?
    var onClose: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let items: [(id: String?, name: String, symbol: String)] = [
        (nil,         "Shuffle All", "shuffle"),
        ("cities",    "Cities",      "building.2.fill"),
        ("coastal",   "Coastal",     "water.waves"),
        ("mountains", "Mountains",   "mountain.2.fill"),
        ("desert",    "Desert",      "sun.haze.fill"),
    ]

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupHeader()
        setupTable()
    }

    // MARK: Setup

    private func setupBackground() {
        // Deep frosted glass — dark blur + subtle tint, matching system sidebar style
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blur)

        // Right-edge gradient to soften where sidebar meets video content
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.25).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint   = CGPoint(x: 1, y: 0)
        gradient.frame = CGRect(x: view.bounds.width - 40, y: 0, width: 40, height: view.bounds.height)
        blur.contentView.layer.addSublayer(gradient)
    }

    private func setupHeader() {
        let label = UILabel()
        label.text = "Categories"
        label.font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.5)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 52),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
        ])
    }

    private func setupTable() {
        tableView.backgroundColor = .clear
        // separatorStyle unavailable on tvOS; cells use contentView backgrounds instead
        tableView.showsVerticalScrollIndicator = false
        tableView.remembersLastFocusedIndexPath = true
        tableView.register(SidebarCell.self, forCellReuseIdentifier: "cell")
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 120),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: Remote — Menu closes the sidebar

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .menu {
            onClose?()
            return
        }
        super.pressesEnded(presses, with: event)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SidebarViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SidebarCell
        let item = items[indexPath.row]
        cell.configure(name: item.name, symbol: item.symbol, active: item.id == model?.activeSection)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 80 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        model?.loadSection(items[indexPath.row].id)
        onClose?()
    }
}

// MARK: - SidebarCell

private class SidebarCell: UITableViewCell {

    private let iconView  = UIImageView()
    private let nameLabel = UILabel()
    private let check     = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        // Remove the default blue selection flash — focus ring handles highlighting
        selectedBackgroundView = UIView()

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        nameLabel.textColor = .white
        nameLabel.font = UIFont.systemFont(ofSize: 32, weight: .light)

        check.image = UIImage(systemName: "checkmark")
        check.tintColor = .white
        check.contentMode = .scaleAspectFit

        [iconView, nameLabel, check].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 22),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: check.leadingAnchor, constant: -16),

            check.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            check.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 26),
            check.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, symbol: String, active: Bool) {
        iconView.image = UIImage(systemName: symbol)
        nameLabel.text = name
        check.isHidden = !active
        // Dim inactive, brighten active
        let alpha: CGFloat = active ? 1.0 : 0.6
        iconView.alpha  = alpha
        nameLabel.alpha = alpha
    }

    // tvOS focus: scale up + brighten when focused, reset when unfocused
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations {
            if self.isFocused {
                self.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
                self.nameLabel.font = UIFont.systemFont(ofSize: 32, weight: .medium)
                self.iconView.alpha = 1.0; self.nameLabel.alpha = 1.0
            } else {
                self.contentView.backgroundColor = .clear
                self.nameLabel.font = UIFont.systemFont(ofSize: 32, weight: .light)
                let a: CGFloat = self.check.isHidden ? 0.6 : 1.0
                self.iconView.alpha = a; self.nameLabel.alpha = a
            }
        }
    }

    // Required for tvOS focus to enter cells
    override var canBecomeFocused: Bool { true }
}
