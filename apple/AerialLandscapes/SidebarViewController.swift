//
//  SidebarViewController.swift
//  AerialLandscapes
//
//  Translucent frosted-glass sidebar for category selection.
//  — view.backgroundColor = .clear so UIVisualEffectView shows video behind it
//  — No right-side checkmark (it reserved space even when hidden, truncating labels)
//  — Active state shown with a left accent dot + full-brightness text
//  — Tight 28pt left indent aligns "Categories" header, icons, and labels
//

import UIKit

// MARK: - SidebarViewController

class SidebarViewController: UIViewController {

    weak var model: StreamingPlayerModel?
    var onClose:   (() -> Void)?
    var onCancel:  (() -> Void)?   // called when user presses Menu (cancel preview)

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
        view.backgroundColor = .clear   // let the blur show video underneath

        // .regular style is lighter/more transparent than .dark,
        // making the video more visible through the frosted glass
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Reduce overall opacity for extra translucency on top of the blur
        blur.alpha = 0.82
        view.addSubview(blur)
    }

    private func setupHeader() {
        let label = UILabel()
        label.text = "Categories"
        label.font = UIFont.systemFont(ofSize: 26, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.45)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            // 28 pt matches the cell's leading indent exactly
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
        ])
    }

    private func setupTable() {
        tableView.backgroundColor = .clear
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
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 116),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    // MARK: Remote

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .menu {
            onCancel?()   // revert preview before closing
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

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 78 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Section is already previewing — commit it and close
        model?.loadSection(items[indexPath.row].id)
        onClose?()
    }

    // Fire a live preview as soon as focus moves to a row
    func tableView(_ tableView: UITableView,
                   didUpdateFocusIn context: UITableViewFocusUpdateContext,
                   with coordinator: UIFocusAnimationCoordinator) {
        guard let next = context.nextFocusedIndexPath else { return }
        model?.previewSection(items[next.row].id)
    }
}

// MARK: - SidebarCell

private class SidebarCell: UITableViewCell {

    // Left accent dot — visible when item is the active section
    private let activeDot = UIView()
    private let iconView  = UIImageView()
    private let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = UIView()   // suppress default selection flash

        // Active dot: 4 × 40 pt white bar flush to leading edge
        activeDot.backgroundColor = .white
        activeDot.layer.cornerRadius = 2
        activeDot.isHidden = true

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        nameLabel.textColor = .white
        nameLabel.font = UIFont.systemFont(ofSize: 32, weight: .light)
        nameLabel.numberOfLines = 1
        // Never truncate — if the label is too narrow it's a layout bug, not a content issue
        nameLabel.adjustsFontSizeToFitWidth = false
        nameLabel.lineBreakMode = .byClipping

        [activeDot, iconView, nameLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            // Accent dot: 4 pt wide, 40 pt tall, centred vertically, flush left
            activeDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            activeDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            activeDot.widthAnchor.constraint(equalToConstant: 4),
            activeDot.heightAnchor.constraint(equalToConstant: 40),

            // Icon: 28 pt leading indent, 26×26 pt
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            // Label: immediately after icon, extends to 28 pt from right edge —
            // no checkmark reservation so "Mountains" and all labels have full room
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, symbol: String, active: Bool) {
        iconView.image  = UIImage(systemName: symbol)
        nameLabel.text  = name
        activeDot.isHidden = !active
        let alpha: CGFloat = active ? 1.0 : 0.55
        iconView.alpha  = alpha
        nameLabel.alpha = alpha
        nameLabel.font  = UIFont.systemFont(ofSize: 32, weight: active ? .regular : .light)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations {
            if self.isFocused {
                self.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
                self.nameLabel.font    = UIFont.systemFont(ofSize: 32, weight: .medium)
                self.iconView.alpha    = 1.0
                self.nameLabel.alpha   = 1.0
            } else {
                self.contentView.backgroundColor = .clear
                // Restore font weight to match active/inactive state
                let active = !self.activeDot.isHidden
                self.nameLabel.font  = UIFont.systemFont(ofSize: 32, weight: active ? .regular : .light)
                let alpha: CGFloat   = active ? 1.0 : 0.55
                self.iconView.alpha  = alpha
                self.nameLabel.alpha = alpha
            }
        }
    }

    override var canBecomeFocused: Bool { true }
}
