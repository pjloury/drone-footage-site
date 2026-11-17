// DevMode.swift
// Hidden developer mode toggled by 5 consecutive taps in the center of the
// screen (see ContentView.registerDevTap). Persisted in UserDefaults.
//
// Intentional duplicate of apple/AerialLandscapes/DevMode.swift — same
// per-target synced-folder constraint as MinimapView.swift in this folder
// (see that file's header comment for the full explanation). Keep the two
// in sync by hand. Each app has its own UserDefaults sandbox regardless —
// using the same key name is just for readability, not shared storage.

import Foundation

enum DevMode {
    private static let key = "aerialDevMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func toggle() { isEnabled = !isEnabled }
}
