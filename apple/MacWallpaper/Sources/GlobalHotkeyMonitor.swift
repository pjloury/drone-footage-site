// GlobalHotkeyMonitor.swift
// System-wide hotkeys via NSEvent global monitor.
// Requires Input Monitoring permission — macOS prompts automatically on first use.
//
// Bindings (⌃⌥ chosen because macOS does not use this combo for any system shortcut):
//   ⌃⌥ →   Next video
//   ⌃⌥ ←   Previous video
//   ⌃⌥ Space   Pause / Resume

// Compiled out of the Mac App Store build: global event monitors need Input
// Monitoring, which the sandbox forbids, and the addGlobalMonitorForEvents
// symbol alone can trip App Review static analysis.
#if !MAS
import AppKit

private let kRight: UInt16 = 124
private let kLeft:  UInt16 = 123
private let kSpace: UInt16 = 49
private let kTarget: NSEvent.ModifierFlags = [.control, .option]

@MainActor
final class GlobalHotkeyMonitor {

    private var globalMonitor: Any?
    private var localMonitor:  Any?

    func start(onNext: @escaping @MainActor () -> Void,
               onPrev: @escaping @MainActor () -> Void,
               onToggle: @escaping @MainActor () -> Void) {

        let dispatch: (NSEvent) -> Void = { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == kTarget else { return }
            DispatchQueue.main.async {
                switch event.keyCode {
                case kRight: onNext()
                case kLeft:  onPrev()
                case kSpace: onToggle()
                default: break
                }
            }
        }

        // Global: fires when another app is foreground
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: dispatch)
        // Local: fires when this app is foreground (rare for a menu-bar-only app, but correct)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            dispatch(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
    }
}
#endif
