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

        // The desktop wallpaper (this running app) and the screen saver are two
        // separate macOS mechanisms, so there's no single toggle: the app draws
        // desktop-level windows while it runs; the screen saver is a .saver the
        // OS loads when idle. This installs the bundled .saver and opens the
        // Screen Saver settings pane so the user can pick it.
        //
        // The App Store sandbox can't write to ~/Library/Screen Savers and won't
        // pass review with a bundled plugin, so the MAS build omits this entirely.
        #if !MAS
        let install = NSMenuItem(title: "Install Screen Saver…",
                                 action: #selector(installScreenSaver), keyEquivalent: "")
        install.target = self
        menu.addItem(install)

        menu.addItem(.separator())
        #endif
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    #if !MAS
    /// Locate the bundled/sibling .saver, copy it into ~/Library/Screen Savers,
    /// then open System Settings → Screen Saver.
    @objc private func installScreenSaver() {
        guard let src = Self.locateSaver() else {
            return presentAlert(style: .warning,
                title: "Screen Saver not found",
                info: "The Aerial Landscapes screen saver bundle could not be located next to or inside the app.")
        }
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers", isDirectory: true)
        let dest = dir.appendingPathComponent(src.lastPathComponent)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: src, to: dest)
        } catch {
            return presentAlert(style: .critical,
                title: "Install failed", info: error.localizedDescription)
        }
        // Open the Screen Saver settings pane (Ventura+ Settings URL).
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
        presentAlert(style: .informational,
            title: "Screen Saver installed",
            info: "“Aerial Landscapes” is now available in System Settings → Screen Saver.")
    }

    /// Find the bundled .saver without depending on its exact filename:
    /// 1) embedded in the app's PlugIns, 2) sibling in the build dir (dev).
    private static func locateSaver() -> URL? {
        let fm = FileManager.default
        func firstSaver(in dir: URL?) -> URL? {
            guard let dir,
                  let items = try? fm.contentsOfDirectory(at: dir,
                      includingPropertiesForKeys: nil) else { return nil }
            return items.first { $0.pathExtension == "saver" }
        }
        if let p = firstSaver(in: Bundle.main.builtInPlugInsURL) { return p }
        return firstSaver(in: Bundle.main.bundleURL.deletingLastPathComponent())
    }

    private func presentAlert(style: NSAlert.Style, title: String, info: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = info
        alert.runModal()
    }
    #endif

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
