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
    private let headerLabel = UILabel()

    // Sidebar display state: category list or video picker for a section
    private enum SidebarLevel {
        case categories
        case videos(sectionId: String, sectionName: String)
    }
    private var level: SidebarLevel = .categories

    private let categories: [(id: String?, name: String, symbol: String)] = [
        (nil,         "Shuffle All", "shuffle"),
        ("cities",    "Cities",      "building.2.fill"),
        ("coastal",   "Coastal",     "water.waves"),
        ("mountains", "Mountains",   "mountain.2.fill"),
        ("desert",    "Desert",      "sun.haze.fill"),
    ]

    // Videos shown in the picker level, sorted alphabetically
    private var pickerVideos: [Video] = []

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
        headerLabel.text = "Categories"
        headerLabel.font = UIFont.systemFont(ofSize: 26, weight: .semibold)
        headerLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)
        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
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

    // MARK: Dev mode

    /// Called by PlayerViewController when DevMode is toggled — refresh gold dots.
    func reloadForDevMode() {
        tableView.reloadData()
        updateHeaderForLevel()
    }

    private func updateHeaderForLevel() {
        switch level {
        case .categories:
            headerLabel.text = DevMode.isEnabled ? "Categories ◆" : "Categories"
            headerLabel.textColor = DevMode.isEnabled
                ? UIColor(red: 0.85, green: 0.60, blue: 0.10, alpha: 0.7)
                : UIColor.white.withAlphaComponent(0.45)
        case .videos(_, let name):
            headerLabel.text = name
            headerLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        }
    }

    private func openVideoPicker(sectionId: String, sectionName: String) {
        pickerVideos = VideoConfig.allVideos
            .filter { $0.geozone == sectionId }
            .sorted { $0.displayTitle < $1.displayTitle }
        level = .videos(sectionId: sectionId, sectionName: sectionName)
        updateHeaderForLevel()
        tableView.reloadData()
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        UIView.transition(with: tableView, duration: 0.28,
                          options: .transitionCrossDissolve, animations: nil)
    }

    private func backToCategories() {
        level = .categories
        updateHeaderForLevel()
        tableView.reloadData()
        UIView.transition(with: tableView, duration: 0.28,
                          options: .transitionCrossDissolve, animations: nil)
    }

    // MARK: Remote

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses where press.type == .menu {
            if case .videos = level {
                // Back arrow in video picker returns to categories
                backToCategories()
                return
            }
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
        switch level {
        case .categories:           return categories.count
        case .videos:               return pickerVideos.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SidebarCell
        switch level {
        case .categories:
            let item = categories[indexPath.row]
            cell.configure(name: item.name, symbol: item.symbol,
                           active: item.id == model?.activeSection,
                           devDot: item.id != nil && DevMode.isEnabled)
        case .videos:
            let v = pickerVideos[indexPath.row]
            let isCurrentVideo = v.displayTitle == (model?.currentTitle ?? "")
            cell.configure(name: v.displayTitle, symbol: "film",
                           active: isCurrentVideo,
                           devDot: false)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 78 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch level {
        case .categories:
            let item = categories[indexPath.row]
            if DevMode.isEnabled, let sectionId = item.id {
                // In dev mode: commit the section but stay open to pick a video
                model?.loadSection(sectionId)
                openVideoPicker(sectionId: sectionId, sectionName: item.name)
            } else {
                model?.loadSection(item.id)
                onClose?()
            }
        case .videos:
            let v = pickerVideos[indexPath.row]
            model?.jumpToVideo(id: v.id)
            onClose?()
        }
    }

    // Fire a live preview as soon as focus moves to a row (categories level only)
    func tableView(_ tableView: UITableView,
                   didUpdateFocusIn context: UITableViewFocusUpdateContext,
                   with coordinator: UIFocusAnimationCoordinator) {
        guard let next = context.nextFocusedIndexPath else { return }
        if case .categories = level {
            model?.previewSection(categories[next.row].id)
        }
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

    func configure(name: String, symbol: String, active: Bool, devDot: Bool) {
        iconView.image  = UIImage(systemName: symbol)
        nameLabel.text  = name
        activeDot.isHidden = !active
        // Gold dot when dev mode is on for a category row, white otherwise
        activeDot.backgroundColor = devDot
            ? UIColor(red: 0.85, green: 0.60, blue: 0.10, alpha: 1)
            : .white
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
