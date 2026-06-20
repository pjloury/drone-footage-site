import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let wallpaper: WallpaperWindowController

    init(wallpaper: WallpaperWindowController) {
        self.wallpaper = wallpaper
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "play.rectangle.fill",
                                           accessibilityDescription: "Wallpaper")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        wallpaper.onStatusChanged = { [weak self] in self?.refreshIcon() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        // Video name (or em-dash if nothing loaded yet)
        let caption = wallpaper.currentVideo?.caption ?? "—"
        menu.addItem(disabled(caption))
        menu.addItem(.separator())

        // Menu-click targets (no key equivalents here — hotkeys are global ⌃⌥ combos)
        let prev = NSMenuItem(title: "Previous  ⌃⌥←", action: #selector(prevVideo), keyEquivalent: "")
        prev.target = self
        prev.isEnabled = wallpaper.historyCount > 0
        menu.addItem(prev)

        let next = NSMenuItem(title: "Next  ⌃⌥→", action: #selector(nextVideo), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let toggle = NSMenuItem(
            title: (wallpaper.isPlaying ? "Pause" : "Resume") + "  ⌃⌥Space",
            action: #selector(togglePlayback),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func refreshIcon() {
        let name: String
        switch wallpaper.streamStatus {
        case .buffering, .loading: name = "pause.circle.fill"
        case .playing:             name = "play.rectangle.fill"
        case .paused:              name = "pause.rectangle.fill"
        }
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Wallpaper")
        statusItem.button?.image?.isTemplate = true
    }

    @objc private func nextVideo()      { wallpaper.next() }
    @objc private func prevVideo()      { wallpaper.prev() }
    @objc private func togglePlayback() { wallpaper.isPlaying ? wallpaper.pause() : wallpaper.resume() }
}
