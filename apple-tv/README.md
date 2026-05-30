# Drone Footage — Apple TV App

tvOS wrapper for `drones.pjloury.com`. Loads the site in a full-screen
WKWebView and translates Siri Remote presses into the keyboard events the
site already handles.

## Remote → app navigation

| Siri Remote gesture | Action |
|---|---|
| Swipe / click Left | Previous clip |
| Swipe / click Right | Next clip |
| Swipe / click Up | Toggle name card |
| Swipe / click Down | Toggle name card |
| Click (select) | Confirm section selection |
| Menu button | Close section menu |
| Play/Pause | Open / close section menu |

Once the section menu is open, Up/Down navigate the list and Select confirms.

## Setting up the Xcode project

1. Open Xcode → **File › New › Project**
2. Choose **tvOS › App**
3. Product Name: `DroneFootageTV`
4. Bundle Identifier: `com.pjloury.dronefootage`
5. Language: **Swift**, Interface: **SwiftUI**, Life Cycle: **SwiftUI App**
6. Uncheck "Include Tests" (optional)
7. **Delete** the generated `ContentView.swift` and `DroneFootageTVApp.swift`
8. **Add** the three source files from this directory:
   - `DroneFootageTV/App.swift`
   - `DroneFootageTV/ContentView.swift`
   - `DroneFootageTV/TVWebViewController.swift`
9. Replace the generated `Info.plist` content with `DroneFootageTV/Info.plist`
10. In **Signing & Capabilities**, select your Apple Developer team

## App Store submission checklist

- [ ] Create a 1920×1080 TV top-shelf image in `Assets.xcassets`
- [ ] Add a 400×240 app icon in `Assets.xcassets`
- [ ] Archive → Distribute → App Store Connect
- [ ] App Store listing: category = **Entertainment**

## How it works

- **Desktop mode**: a `WKUserScript` injected at `atDocumentStart` overrides
  `navigator.userAgent` so the site's `IS_MOBILE` flag is false before any
  JS runs, meaning full-resolution video is served.
- **TV mode**: the URL includes `?tv=1`, which tells the site to keep nav
  arrows visible and enable keyboard-driven section navigation.
- **Remote input**: `pressesBegan` intercepts `UIPress` events from the Siri
  Remote and dispatches synthetic `KeyboardEvent` objects on `document`.
- **Retry on failure**: if the page fails to load (e.g. Apple TV woke from
  sleep with no Wi-Fi), a 4-second retry fires automatically.
