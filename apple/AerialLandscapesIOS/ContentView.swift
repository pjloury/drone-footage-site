import SwiftUI

struct ContentView: View {
    @StateObject private var model = AerialPlayerModel()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AerialPlayerView(player: model.player)
                .ignoresSafeArea()
                .background(Color.black)

            // Category switcher — single button that reveals options on tap.
            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    // AirPlay button — revealed only when nearby devices exist.
                    if model.airplayAvailable {
                        AirPlayButton()
                            .frame(width: 34, height: 34)
                            .padding(.horizontal, 6)
                            .background(Capsule().fill(Color.black.opacity(0.35)))
                            .transition(.opacity)
                    }
                    Menu {
                        ForEach(PlaybackMode.allCases) { m in
                            Button {
                                model.setMode(m)
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
                .padding(.leading, 24)
                .padding(.bottom, 32)
        }
    }
}
