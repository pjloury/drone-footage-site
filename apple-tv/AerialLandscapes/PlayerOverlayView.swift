//
//  PlayerOverlayView.swift
//  AerialLandscapes
//
//  SwiftUI overlay drawn on top of the fullscreen AVPlayer:
//  - Left/right nav arrows (glass, tapered, flash on press)
//  - Title caption (bottom-left, toggleable)
//  - Section name badge (top-right when not shuffling)
//  - Section picker dropdown (top-right, same position as on the website)
//

import SwiftUI

// MARK: - Root overlay

struct PlayerOverlayView: View {
    @ObservedObject var model: StreamingPlayerModel

    var body: some View {
        ZStack {
            navArrows
            sectionBadge
            titleCaption
            if model.showSectionPicker {
                SectionPickerOverlay(model: model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.showSectionPicker)
        .animation(.easeInOut(duration: 0.4),  value: model.showTitleCard)
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

    // ── Section badge (top-right, only when a section is active) ─────────

    private var sectionBadge: some View {
        VStack {
            HStack {
                Spacer()
                if let section = model.activeSection,
                   let name = StreamingPlayerModel.sections.first(where: { $0.id == section })?.name {
                    Text(name.uppercased())
                        .font(.system(size: 18, weight: .light, design: .default))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .padding(.top, 44)
                        .padding(.trailing, 60)
                        .transition(.opacity)
                }
            }
            Spacer()
        }
    }

    // ── Title caption (bottom-left, like the website) ─────────────────────

    private var titleCaption: some View {
        VStack {
            Spacer()
            HStack {
                if model.showTitleCard {
                    Text(model.currentTitle)
                        .font(.system(size: 36, weight: .light, design: .default))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 0)
                        .padding(.leading, 80)
                        .padding(.bottom, 70)
                        .transition(.opacity)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Nav arrow

struct NavArrowView: View {
    let pointsLeft: Bool
    let lit: Bool

    var body: some View {
        GeometryReader { geo in
            let arrowHeight = geo.size.height * 0.38
            let arrowWidth  = CGFloat(70)

            VStack {
                Spacer()
                ZStack {
                    TaperedArrowShape(pointsLeft: pointsLeft)
                        .fill(.white.opacity(0.08))
                    TaperedArrowShape(pointsLeft: pointsLeft)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                    // Blur layer via material in a clipped container
                    TaperedArrowShape(pointsLeft: pointsLeft)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55)

                    Image(systemName: pointsLeft ? "chevron.left" : "chevron.right")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .offset(x: pointsLeft ? 4 : -4)
                }
                .frame(width: arrowWidth, height: arrowHeight)
                .opacity(lit ? 1.0 : 0.35)
                .animation(.easeOut(duration: lit ? 0.25 : 1.0), value: lit)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: pointsLeft ? .leading : .trailing)
        }
    }
}

// Tapered glass panel: flat on the screen edge, pinched inward on the opposite edge
struct TaperedArrowShape: Shape {
    let pointsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pinch = rect.height * 0.15
        if pointsLeft {
            p.move(to:    CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + pinch))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - pinch))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to:    CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + pinch))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - pinch))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Section picker overlay

struct SectionPickerOverlay: View {
    @ObservedObject var model: StreamingPlayerModel

    // Picker items: 0 = Shuffle All, 1-4 = sections
    private let items: [(id: String?, name: String, icon: String?)] = [
        (nil,        "Shuffle All", "shuffle"),
        ("cities",   "Cities",     nil),
        ("coastal",  "Coastal",    nil),
        ("mountains","Mountains",  nil),
        ("desert",   "Desert",     nil),
    ]

    var body: some View {
        VStack(alignment: .trailing) {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items.indices, id: \.self) { idx in
                        pickerRow(for: items[idx], at: idx)
                        if idx == 0 {
                            Divider()
                                .background(.white.opacity(0.12))
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.black.opacity(0.65))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                                .opacity(0.7)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.top, 70)
                .padding(.trailing, 60)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func pickerRow(for item: (id: String?, name: String, icon: String?), at idx: Int) -> some View {
        let isFocused = idx == model.pickerFocusIndex
        let isActive  = item.id == model.activeSection

        HStack(spacing: 0) {
            // Active dot
            Circle()
                .fill(isActive ? Color.white : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.leading, 18)
                .padding(.trailing, 10)

            // Optional icon (shuffle row)
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(isFocused ? .white : .white.opacity(0.55))
                    .frame(width: 20)
                    .padding(.trailing, 8)
            } else {
                Color.clear.frame(width: 28)
            }

            Text(item.name)
                .font(.system(size: 24, weight: isActive ? .medium : .light))
                .foregroundColor(isFocused ? .white : .white.opacity(0.55))

            Spacer(minLength: 24)
        }
        .frame(minWidth: 220)
        .padding(.vertical, 12)
        .background(isFocused ? Color.white.opacity(0.12) : Color.clear)
    }
}
