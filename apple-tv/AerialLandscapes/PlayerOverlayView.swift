//
//  PlayerOverlayView.swift
//  AerialLandscapes
//
//  SwiftUI overlay: nav arrows, title caption, section button (always visible),
//  minimap (bottom-right), and the section picker dropdown.
//

import SwiftUI

// MARK: - Root overlay

struct PlayerOverlayView: View {
    @ObservedObject var model: StreamingPlayerModel

    var body: some View {
        ZStack {
            navArrows
            topRightControls
            bottomRow
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

    // ── Top-right: section button (always visible) ────────────────────────
    // Mirrors the website's shuffle button in the top-right corner.
    // Play/Pause on the Siri Remote opens the picker.

    private var topRightControls: some View {
        VStack {
            HStack {
                Spacer()
                SectionButton(model: model)
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
                // Title caption — always visible, matching the desktop web app
                Text(model.currentTitle)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .padding(.leading, 80)
                    .padding(.bottom, 70)
                Spacer()
                // Minimap
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

// MARK: - Section button (always visible, like the website's top-right shuffle icon)

struct SectionButton: View {
    @ObservedObject var model: StreamingPlayerModel

    var label: String {
        guard let sec = model.activeSection,
              let name = StreamingPlayerModel.sections.first(where: { $0.id == sec })?.name
        else { return "" }
        return name.uppercased()
    }

    var body: some View {
        HStack(spacing: 8) {
            // Shuffle icon — always shown; becomes filled when in shuffle mode
            Image(systemName: model.activeSection == nil ? "shuffle" : "line.3.horizontal.decrease")
                .font(.system(size: 15, weight: .light))
                .foregroundColor(.white.opacity(0.8))

            if model.activeSection != nil {
                Text(label)
                    .font(.system(size: 16, weight: .light))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.white.opacity(model.showSectionPicker ? 0.5 : 0.25), lineWidth: 1)
                )
        )
        .opacity(model.showSectionPicker ? 1.0 : 0.75)
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
                    TaperedArrowShape(pointsLeft: pointsLeft)
                        .fill(.ultraThinMaterial)
                        .opacity(0.55)
                    TaperedArrowShape(pointsLeft: pointsLeft)
                        .fill(.white.opacity(0.06))
                    TaperedArrowShape(pointsLeft: pointsLeft)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
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

    private let items: [(id: String?, name: String, icon: String?)] = [
        (nil,         "Shuffle All", "shuffle"),
        ("cities",    "Cities",      nil),
        ("coastal",   "Coastal",     nil),
        ("mountains", "Mountains",   nil),
        ("desert",    "Desert",      nil),
    ]

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items.indices, id: \.self) { idx in
                        pickerRow(for: items[idx], at: idx)
                        if idx == 0 {
                            Divider().background(.white.opacity(0.12)).padding(.horizontal, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.black.opacity(0.65))
                        .overlay(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
                )
                .shadow(color: .black.opacity(0.4), radius: 20)
                .padding(.top, 106)    // sits just below the section button
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
            Circle()
                .fill(isActive ? Color.white : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.leading, 18).padding(.trailing, 10)

            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(isFocused ? .white : .white.opacity(0.55))
                    .frame(width: 20).padding(.trailing, 8)
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
