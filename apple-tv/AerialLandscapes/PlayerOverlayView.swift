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
            topRight
            bottomRow
        }
    }

    // ── Nav arrows ────────────────────────────────────────────────────────

    private var navArrows: some View {
        HStack(spacing: 0) {
            NavArrowView(pointsLeft: true,  lit: model.leftFlash)
            Spacer()
            NavArrowView(pointsLeft: false, lit: model.rightFlash)
        }
        .ignoresSafeArea()
    }

    // ── Top-right: section indicator + open-sidebar hint ─────────────────
    // Shows the active section name (or the shuffle icon) so users always
    // know what's playing and that ↑ / Play-Pause opens the category menu.

    private var topRight: some View {
        VStack {
            HStack {
                Spacer()
                SectionIndicator(model: model)
                    .padding(.top, 44)
                    .padding(.trailing, 60)
            }
            Spacer()
        }
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
                    // Accessibility ID lets UI tests read the exact caption.
                    .accessibilityIdentifier("video-caption")
                    .accessibilityValue(model.currentTitle)

                // Zero-size element that exposes currentQueueIndex as an
                // accessibility value. .hidden() removes from a11y tree, so
                // use .opacity(0) + tiny frame to keep it in the tree.
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

// MARK: - Section indicator (informational; not interactive)

struct SectionIndicator: View {
    @ObservedObject var model: StreamingPlayerModel

    private var sectionName: String? {
        guard let id = model.activeSection else { return nil }
        return StreamingPlayerModel.sections.first(where: { $0.id == id })?.name
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .light))
                .foregroundColor(.white.opacity(0.7))

            if let name = sectionName {
                Text(name.uppercased())
                    .font(.system(size: 15, weight: .light))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
        )
        .opacity(0.75)
    }
}

// MARK: - Nav arrow

struct NavArrowView: View {
    let pointsLeft: Bool
    let lit: Bool

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
                .opacity(lit ? 1.0 : 0.35)
                .animation(.easeOut(duration: lit ? 0.25 : 1.0), value: lit)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: pointsLeft ? .leading : .trailing)
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
