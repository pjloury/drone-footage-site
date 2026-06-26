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

    private var heartbeatTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WallpaperLog.shared.log("app", "=== launch === pid=\(ProcessInfo.processInfo.processIdentifier) screens=\(NSScreen.screens.count) log=\(WallpaperLog.shared.fileURL.path)")
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

        // Heartbeat: a memory + state line every 30s. If the app dies, the last
        // heartbeat plus any lifecycle lines after it bracket the crash window.
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                let mb = WallpaperLog.memoryFootprintMB()
                WallpaperLog.shared.log("heartbeat",
                    String(format: "mem=%.1fMB screens=%d video=%@ status=%@ history=%d",
                           mb, NSScreen.screens.count,
                           controller.currentVideo?.caption ?? "—",
                           controller.streamStatus.label,
                           controller.historyCount))
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WallpaperLog.shared.log("app", "=== clean terminate ===")
    }
}
