import SwiftUI

struct ContentView: View {
    @StateObject private var model = AerialPlayerModel()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AerialPlayerView(player: model.player)
                .ignoresSafeArea()
                .background(Color.black)

            // Category switcher — top, horizontally scrollable pills.
            VStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlaybackMode.allCases) { m in
                            Button { model.setMode(m) } label: {
                                Text(m.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(model.mode == m ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(model.mode == m
                                            ? Color.white.opacity(0.92)
                                            : Color.black.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
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
