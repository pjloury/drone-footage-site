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
        }
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
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .padding(.leading, 80)
                    .padding(.bottom, 70)
                    .accessibilityIdentifier("video-caption")
                    .accessibilityValue(model.currentTitle)

                Text("\(model.currentQueueIndex)")
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("queue-index")
                    .accessibilityValue("\(model.currentQueueIndex)")

                Spacer()

                if let lat = model.currentLat, let lng = model.currentLng {
                    MinimapView(lat: lat, lng: lng)
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
