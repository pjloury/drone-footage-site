import SwiftUI

struct ContentView: View {
    @StateObject private var model = AerialPlayerModel()
    @State private var coverOpacity = 0.0

    /// Switch categories with a smooth dip-to-black dissolve: fade the screen
    /// out, swap the playlist while hidden, then fade the new footage in.
    private func selectMode(_ m: PlaybackMode) {
        guard m != model.mode else { return }
        withAnimation(.easeInOut(duration: 0.35)) { coverOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            model.setMode(m)
            withAnimation(.easeInOut(duration: 0.55)) { coverOpacity = 0 }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AerialPlayerView(player: model.player)
                .ignoresSafeArea()
                .background(Color.black)

            // Edge tap strips (mirrors web app nav zones) + full-screen swipe.
            GeometryReader { geo in
                let stripW = geo.size.width * 0.2
                ZStack {
                    // Left edge strip → back
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: stripW)
                        .onTapGesture { model.skipBackward() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Right edge strip → forward
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: stripW)
                        .onTapGesture { model.skipForward() }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .ignoresSafeArea()
            // Swipe left = forward, swipe right = back (matches natural reading direction).
            .gesture(DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { v in
                    if v.translation.width < -30 { model.skipForward() }
                    else if v.translation.width > 30 { model.skipBackward() }
                }
            )

            // Nav arrow flash feedback — mirrors tvOS style.
            HStack(spacing: 0) {
                IOSNavArrowView(pointsLeft: true,  lit: model.leftFlash)
                Spacer()
                IOSNavArrowView(pointsLeft: false, lit: model.rightFlash)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Dissolve cover for category transitions.
            Color.black
                .opacity(coverOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Category switcher — single button that reveals options on tap.
            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    // AirPlay button — always visible; picker filters to video routes.
                    AirPlayButton()
                        .frame(width: 34, height: 34)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                    Menu {
                        ForEach(PlaybackMode.allCases) { m in
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
                    } label: {
                        HStack(spacing: 5) {
                            Text(model.mode.label)
                                .font(.system(size: 13, weight: .medium))
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

            // Title caption — bottom-left.
            Text(model.currentTitle)
                .font(.system(.callout, design: .default))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                .padding(.leading, 20)
                .padding(.bottom, 48)
        }
    }
}
