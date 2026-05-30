# Drone Footage — Google TV / Android TV App

Android WebView wrapper for `drones.pjloury.com`, targeting Google TV and
Android TV.  D-pad events from the TV remote are translated into the
keyboard events the site already handles.

## Remote → app navigation

| TV remote button | Action |
|---|---|
| D-pad Left | Previous clip |
| D-pad Right | Next clip |
| D-pad Up | Toggle name card |
| D-pad Down | Toggle name card |
| D-pad Centre / Enter | Confirm section selection |
| Back | Close section menu (or exit app if menu is closed) |
| Play/Pause | Open / close section menu |

Once the section menu is open, Up/Down navigate the list and Centre confirms.

## Prerequisites

- Android Studio Hedgehog (2023.1.1) or later
- Android SDK 34
- Kotlin 1.9.x

## Building

```bash
cd google-tv
./gradlew assembleDebug          # debug APK
./gradlew assembleRelease        # release APK (needs keystore)
```

Sideload the debug APK onto a Google TV or Android TV device:
```bash
adb connect <tv-ip>
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Play Store submission checklist

- [ ] Replace `res/drawable/tv_banner.xml` with a 320×180dp PNG banner
  (the launcher grid image — put a still frame from your best clip here)
- [ ] Replace `res/mipmap-hdpi/ic_launcher.xml` with a real adaptive icon
- [ ] Set up a release signing keystore and configure `signingConfigs` in
  `app/build.gradle`
- [ ] Create a Google Play Console listing → category: **Entertainment**
- [ ] Target Google TV (requires `LEANBACK_LAUNCHER` intent — already in the manifest)

## How it works

- **Desktop mode**: the WebView UA is set to a desktop Chrome string so the
  site's `IS_MOBILE` evaluates to false, serving full-resolution video.
- **TV mode**: `?tv=1` in the URL disables the 5-second nav-arrow hide timer
  and enables keyboard-driven section-menu navigation.
- **Remote input**: `dispatchKeyEvent` intercepts `KEYCODE_DPAD_*` events
  before they reach the WebView and fires synthetic `KeyboardEvent` objects
  via `evaluateJavascript`.
- **Video autoplay**: `mediaPlaybackRequiresUserGesture = false` allows the
  first clip to start without a user interaction, matching the web experience.
