//
//  PlayerOverlayView.swift
//  AerialLandscapes
//
//  Passive overlay drawn on top of the video layers.
//  All user interaction is handled by PlayerViewController / SidebarViewController.
//

import SwiftUI

// MARK: - Root overlay

struct PlayerOverlayView: View {
    @ObservedObject var model: StreamingPlayerModel

    var body: some View {
        ZStack {
            navArrows
            bottomRow
            progressBar
        }
    }

    // ── Translucent progress bar pinned to the bottom edge ────────────────
    // 14px track at 12% white, fill at 55% white, width = playback progress,
    // eased linearly so it advances smoothly. Sized thicker than the website's
    // 4px so it stays clearly visible across a room on a large TV.
    //
    // Fades out/in with the rest of the overlay via `overlayVisible` (see the
    // convention on StreamingPlayerModel.overlayVisible) so it disappears
    // during the crossfade and reappears, empty, with the new clip.

    private var progressBar: some View {
        VStack(spacing: 0) {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12))
                    Rectangle().fill(Color.white.opacity(0.55))
                        .frame(width: max(0, geo.size.width * CGFloat(model.playbackProgress)))
                        .animation(.linear(duration: 0.25), value: model.playbackProgress)
                }
            }
            .frame(height: 14)
        }
        .ignoresSafeArea()
        .opacity(model.overlayVisible ? 1 : 0)
        .animation(.easeInOut(duration: StreamingPlayerModel.overlayFadeDuration),
                   value: model.overlayVisible)
    }

    // ── Nav arrows ────────────────────────────────────────────────────────
    // Invisible at rest (opacity 0) — flash briefly when a direction is pressed.
    // Matches website behaviour: arrows are hidden after the initial hint and
    // only flash during key presses so they never leave a persistent seam.

    private var navArrows: some View {
        HStack(spacing: 0) {
            NavArrowView(pointsLeft: true,  lit: model.leftFlash)
            Spacer()
            NavArrowView(pointsLeft: false, lit: model.rightFlash)
        }
        .ignoresSafeArea()
    }

    // ── Bottom: title caption (left) + minimap (right) ────────────────────

    private var bottomRow: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Text(model.currentTitle)
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(.white)
                    // Deep shadow stack so the title floats clearly over any footage
                    .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.75), radius: 8, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 4)
                    .padding(.leading, 80)
                    .padding(.bottom, 70)
                    // Slide right when the sidebar is open so the caption
                    // clears the sidebar edge (animated from PlayerViewController).
                    .offset(x: model.captionOffset)
                    // Fade out at crossfade start, fade in at the midpoint —
                    // mirrors the website's 0.6s ease-in-out caption fade.
                    .opacity(model.overlayVisible ? 1 : 0)
                    .animation(.easeInOut(duration: StreamingPlayerModel.overlayFadeDuration),
                               value: model.overlayVisible)
                    .accessibilityIdentifier("video-caption")
                    .accessibilityValue(model.currentTitle)

                Text("\(model.currentQueueIndex)")
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("queue-index")
                    .accessibilityValue("\(model.currentQueueIndex)")

                // Hidden probe: lets UI tests assert that the VISIBLE video
                // actually kept playing (currentTime advanced), not merely that
                // the queue-index state machine completed.
                Text("\(model.stuckEventCount)")
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("stuck-count")
                    .accessibilityValue("\(model.stuckEventCount)")

                Spacer()

                if let lat = model.currentLat, let lng = model.currentLng {
                    MinimapView(lat: lat, lng: lng)
                        // Fade out at crossfade start, fade in at the midpoint —
                        // same lifecycle as the caption, so the map image (and
                        // any zone change, e.g. California → US) swaps while
                        // invisible instead of flickering.
                        .opacity(model.overlayVisible ? 1 : 0)
                        .animation(.easeInOut(duration: StreamingPlayerModel.overlayFadeDuration),
                                   value: model.overlayVisible)
                        .padding(.trailing, 60)
                        .padding(.bottom, 60)
                        .transition(.opacity)
                }
            }
        }
    }
}

// MARK: - Nav arrow
//
// Replicates the website's nav-flash CSS keyframe exactly:
//
//   0 %   opacity 0
//   10%   opacity 1   (0 → 1 over 240 ms  — quick fade-in)
//   55%   opacity 1   (hold at full opacity until 1320 ms)
//   100%  opacity 0   (1 → 0 over 1080 ms — slow fade-out)
//   total: 2400 ms
//
// The arrow is fully invisible at rest so ultraThinMaterial never
// leaves a persistent frosted seam at the screen edges.

struct NavArrowView: View {
    let pointsLeft: Bool
    let lit: Bool         // becomes true on press, false 2.4 s later

    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                ZStack {
                    TaperedArrowShape(pointsLeft: pointsLeft).fill(.ultraThinMaterial).opacity(0.55)
                    TaperedArrowShape(pointsLeft: pointsLeft).fill(.white.opacity(0.06))
                    TaperedArrowShape(pointsLeft: pointsLeft).stroke(.white.opacity(0.18), lineWidth: 1)
                    Image(systemName: pointsLeft ? "chevron.left" : "chevron.right")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .offset(x: pointsLeft ? 4 : -4)
                }
                .frame(width: 70, height: geo.size.height * 0.38)
                .opacity(opacity)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: pointsLeft ? .leading : .trailing)
        }
        .onChange(of: lit) {
            guard lit else { return }   // only fire on rising edge
            // 0 → 1 in 240 ms (10% of 2400 ms)
            withAnimation(.easeOut(duration: 0.24)) { opacity = 1.0 }
            // Hold until 1320 ms (55%), then fade out over 1080 ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.32) {
                withAnimation(.easeOut(duration: 1.08)) { opacity = 0.0 }
            }
        }
    }
}

struct TaperedArrowShape: Shape {
    let pointsLeft: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pinch = rect.height * 0.15
        if pointsLeft {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + pinch))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - pinch))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + pinch))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - pinch))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
