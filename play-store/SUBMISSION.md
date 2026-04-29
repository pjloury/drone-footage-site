# Play Store submission — step-by-step

What's done locally vs. what you still have to click through in Play Console.

## ✅ What's already done

```
play-store/
  LISTING.md                       — listing copy (paste into Play Console)
  PRIVACY.html                     — privacy policy (also at /privacy.html on the site)
  icon-512.png                     — 512×512 hi-res icon
  feature-graphic-1024x500.png     — 1024×500 feature graphic
  tv-banner-1280x720.png           — 1280×720 TV banner

googletv-app/
  app/build/outputs/bundle/release/app-release.aab   — signed AAB (upload this)
  app/build/outputs/apk/release/app-release.apk      — signed APK (sideload to test)
  app/release.keystore                               — release signing key (BACK UP)
  keystore.properties                                — passwords (BACK UP, gitignored)
```

## 🟡 What you have to do (one-time, ~30 min of Play Console clicks)

### 1. Create a Google Play Developer account ($25 one-time)
- Go to <https://play.google.com/console/signup>
- Pay the $25 fee.
- Identity verification can take up to a few days for new accounts.

### 2. Sideload-test the APK on a real Google TV first
You almost certainly want to confirm it works on your TV before uploading anywhere.

```bash
# Find your TV's IP under Settings → System → About → Status
adb connect <tv-ip>:5555
adb install googletv-app/app/build/outputs/apk/release/app-release.apk
```

The first time, the TV will ask you to authorize the development machine.

After install, the app shows up under "Apps" / "Your apps" on the home screen with the new banner.

### 3. Take screenshots from the TV
Required by Play Console:

- **TV screenshots:** at least 3, max 8, 1280×720 or 1920×1080.
  - Open the app on the TV.
  - On Google TV, hold the back button to bring up the screenshot prompt — or use `adb exec-out screencap -p > screenshot-1.png` from your Mac.
  - Suggested shots: (1) opening welcome card, (2) a coastal clip mid-playback with the mini-map visible, (3) a mountain clip with the GPS dot, (4) the section selector menu open, (5) a desert clip.

The feature graphic and TV banner are already generated in `play-store/`.

### 4. Create the app in Play Console

1. Play Console → "Create app"
2. App name: `PJ Loury — Drone Videography`
3. Default language: English (United States)
4. App or game: **App**
5. Free or paid: **Free**
6. Accept the declarations.

### 5. Set up the listing
Go to **Store presence → Main store listing** and paste each field from `play-store/LISTING.md`.

Upload the assets:
- App icon → `play-store/icon-512.png`
- Feature graphic → `play-store/feature-graphic-1024x500.png`
- TV banner → `play-store/tv-banner-1280x720.png`
- TV screenshots → the ones you took in step 3

### 6. Privacy policy URL
Under **Policy → App content → Privacy policy**:

Paste: `https://drones.pjloury.com/privacy.html`

(That URL works as soon as you push this commit — the file is at `privacy.html` in the site root, served by Vercel.)

### 7. Content rating
**Policy → App content → Content rating**:

Answer "No" to everything (no violence, no sexual content, no gambling, no UGC, no ads). Result: **Everyone (E)**.

### 8. Data safety
**Policy → App content → Data safety**:

- Does your app collect or share any of the required user data types? **No** for everything.
  - The PostHog session identifier is anonymous and not tied to a user account; per Play's definitions you don't need to declare it as collected user data, but if you want to be conservative declare "App activity → App interactions" with all toggles **NO** (not collected by your app's code; collected by the website you load).
- Encryption in transit: **Yes** (HTTPS only — `usesCleartextTraffic="false"`).

### 9. Target audience
**Policy → App content → Target audience and content**:

Age groups: 13+ (the only age range that doesn't require COPPA/family-policy compliance docs).

### 10. Ads
**Policy → App content → Ads**:

Does your app contain ads? **No**.

### 11. Government apps / Financial / News / etc.
**No** to all.

### 12. Set up an internal testing track FIRST
**Testing → Internal testing → Create new release**:

1. Upload `googletv-app/app/build/outputs/bundle/release/app-release.aab`
2. Release name: `1.0`
3. Release notes (paste from LISTING.md "What's new"):
   ```
   First release. 50+ aerial drone clips, smooth 1080p, full Google TV remote support.
   ```
4. Add yourself as an internal tester (give Play Console your gmail).
5. Save → Review → Roll out to internal testing.

Internal testing typically goes live within minutes. You'll get an opt-in URL — open it on the TV's browser, opt in, then the app shows up on the Play Store on the TV under "My Apps" within an hour or so.

This gives you one more chance to verify everything before going public.

### 13. Promote internal → production
Once internal testing looks good:

**Testing → Internal testing → Promote release → Production**.

Or do **Production → Create new release** and upload the AAB again (same artifact is fine).

Submit for review. Google's review for a TV app typically takes 1–7 days for a new account.

## 🔴 Critical: back up the keystore

Losing `googletv-app/app/release.keystore` (or its password from `keystore.properties`) means **you can never publish an update to this app** on the Play Store again — every update must be signed with the same key, and the key cannot be regenerated.

Suggested backup:
1. Copy both files to a password manager or encrypted backup:
   ```bash
   tar czf release-keystore-backup.tgz \
     googletv-app/app/release.keystore \
     googletv-app/keystore.properties
   ```
2. Upload `release-keystore-backup.tgz` somewhere durable (1Password / iCloud / encrypted external drive).
3. Optionally enable Google Play App Signing during initial upload (Play Console → "Use Play App Signing") — Google holds the upload key and re-signs releases, so even if you lose your local key Google can issue you a new one.

## Updating the app later
1. Bump `versionCode` and `versionName` in `googletv-app/app/build.gradle`.
2. Make whatever code changes.
3. Rebuild:
   ```bash
   cd googletv-app
   JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew bundleRelease
   ```
4. Upload the new AAB to **Production → Create new release**.

Because the app is just a WebView wrapping `drones.pjloury.com`, most "updates" are actually changes to the website — those ship instantly via Vercel deploy without needing a Play Store update.

Reasons you'd actually need to ship a new APK:
- New D-pad behavior
- New permissions
- Native fullscreen controls
- Bumping `targetSdk` (Google requires this annually)
