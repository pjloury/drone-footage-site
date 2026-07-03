import SwiftUI

struct ContentView: View {
    @StateObject private var model = AerialPlayerModel()

    private func selectMode(_ m: PlaybackMode) {
        guard m != model.mode else { return }
        // setMode dissolves via the player-layer crossfade, so no black cover.
        model.setMode(m)
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
            .transaction { $0.animation = nil }

            // Title caption — bottom-left.
            Text(model.currentTitle)
                .font(.system(.callout, design: .default))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
                .padding(.leading, 20)
                .padding(.bottom, 20)
        }
    }
}
