import SwiftUI

struct ContentView: View {
    @StateObject private var model = AerialPlayerModel()

    // Hidden dev mode — 5 taps in the center of the screen (same exclusion
    // zone as the skip strips, matching tvOS's 5-select-presses and the
    // website's 5-center-clicks) within 3s toggles a persisted flag that
    // gates the individual-video picker in the category Menu below.
    @State private var devModeOn = DevMode.isEnabled
    @State private var devTapCount = 0
    @State private var devTapResetWorkItem: DispatchWorkItem?
    @State private var toastText: String?
    private static let devTapWindow: TimeInterval = 3.0

    private func selectMode(_ m: PlaybackMode) {
        guard m != model.mode else { return }
        // setMode dissolves via the player-layer crossfade, so no black cover.
        model.setMode(m)
    }

    private func registerDevTap() {
        devTapResetWorkItem?.cancel()
        devTapCount += 1
        if devTapCount >= 5 {
            devTapCount = 0
            DevMode.toggle()
            devModeOn = DevMode.isEnabled
            showToast(devModeOn ? "DEV MODE ON" : "DEV MODE OFF")
            return
        }
        let work = DispatchWorkItem { devTapCount = 0 }
        devTapResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.devTapWindow, execute: work)
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.25)) { toastText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.4)) { toastText = nil }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            // Two fixed player layers — opacities crossfade between them.
            ZStack {
                AerialPlayerView(player: model.playerA)
                    .opacity(model.opacityA)
                AerialPlayerView(player: model.playerB)
                    .opacity(model.opacityB)
            }
            .ignoresSafeArea()
            .background(Color.black)

            // Edge tap strips (20% each side) + full-screen swipe.
            // Use simultaneousGesture for drag so the Menu button above is
            // never blocked by gesture-recognizer competition.
            GeometryReader { geo in
                let stripW = geo.size.width * 0.2
                ZStack {
                    // Dev-tap catcher, full-size but UNDER the two skip strips
                    // below in z-order, so a tap only reaches it from the
                    // center ~60% — taps on the skip strips never count
                    // toward the dev-mode counter, same exclusion the
                    // website's center-zone check makes explicit.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { registerDevTap() }
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: stripW)
                        .onTapGesture { model.skipBackward() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: stripW)
                        .onTapGesture { model.skipForward() }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .ignoresSafeArea()
            .simultaneousGesture(DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { v in
                    if v.translation.width < -30 { model.skipForward() }
                    else if v.translation.width > 30 { model.skipBackward() }
                }
            )

            // Nav arrow flash feedback.
            HStack(spacing: 0) {
                IOSNavArrowView(pointsLeft: true,  lit: model.leftFlash)
                Spacer()
                IOSNavArrowView(pointsLeft: false, lit: model.rightFlash)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Progress bar — pinned to bottom edge, mirrors tvOS style.
            VStack(spacing: 0) {
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.12))
                        Rectangle().fill(Color.white.opacity(0.55))
                            .frame(width: max(0, geo.size.width * CGFloat(model.playbackProgress)))
                            .animation(.linear(duration: 0.5), value: model.playbackProgress)
                    }
                }
                .frame(height: 3)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Category switcher — top right.
            // .animation(nil) prevents crossfade animations bleeding into the
            // Menu label and popover options, which caused flickering.
            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    AirPlayButton()
                        .frame(width: 34, height: 34)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                    Menu {
                        ForEach(model.availableModes) { m in
                            // Dev mode: a category (not Shuffle) becomes a
                            // submenu of its individual videos — tapping one
                            // jumps straight to that clip (instant cut, no
                            // crossfade), mirroring tvOS's jumpToVideo.
                            if devModeOn, m.id != "shuffle" {
                                Menu(m.label) {
                                    ForEach(Catalog.shared.ids(in: m.id), id: \.self) { id in
                                        Button(Catalog.shared.caption(forID: id)) {
                                            model.jumpToVideo(id: id)
                                        }
                                    }
                                }
                            } else {
                                Button {
                                    selectMode(m)
                                } label: {
                                    if model.mode == m {
                                        Label(m.label, systemImage: "checkmark")
                                    } else {
                                        Text(m.label)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(model.mode.label)
                                .font(.system(size: 13, weight: .medium))
                            if devModeOn {
                                Circle()
                                    .fill(Color(red: 0.85, green: 0.60, blue: 0.10))
                                    .frame(width: 5, height: 5)
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 8)
                Spacer()
            }
            .transaction { $0.animation = nil }

            // Title caption (bottom-left) + minimap (bottom-right) — mirrors
            // the tvOS/website bottom row.
            HStack(alignment: .bottom) {
                Text(model.currentTitle)
                    .font(.system(.callout, design: .default))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)

                Spacer()

                if let lat = model.currentLat, let lng = model.currentLng {
                    MinimapView(lat: lat, lng: lng)
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.bottom, 20)

            // Dev-mode toggle toast — mirrors tvOS's centered "DEV MODE
            // ON/OFF" flash.
            if let toastText {
                Text(toastText)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(devModeOn ? Color(red: 0.85, green: 0.60, blue: 0.10) : .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}
