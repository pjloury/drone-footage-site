import AppKit

@main
struct MacWallpaperApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wallpaper: WallpaperWindowController?
    private var statusBar: StatusBarController?
    private var hotkeys:   GlobalHotkeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model      = WallpaperPlayerModel()
        let controller = WallpaperWindowController(model: model)
        let bar        = StatusBarController(wallpaper: controller)
        let monitor    = GlobalHotkeyMonitor()

        monitor.start(
            onNext:   { controller.next() },
            onPrev:   { controller.prev() },
            onToggle: { controller.isPlaying ? controller.pause() : controller.resume() }
        )

        wallpaper = controller
        statusBar = bar
        hotkeys   = monitor
    }
}
