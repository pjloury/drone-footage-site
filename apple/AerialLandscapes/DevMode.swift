// DevMode.swift
// Hidden developer mode toggled by 5 consecutive select-button taps.
// Persisted in UserDefaults; shared across tvOS and iOS targets.

import Foundation

enum DevMode {
    private static let key = "aerialDevMode"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func toggle() { isEnabled = !isEnabled }
}
