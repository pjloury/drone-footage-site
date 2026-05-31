//
//  MinimapView.swift
//  AerialLandscapes
//
//  Shows the exact same map aesthetic as the website: screenshots of the
//  SVG land-mass maps (with white outlines on dark fill) used as static
//  PNG backgrounds, with the GPS dot drawn on top using the same
//  equirectangular/Mercator projections as the web app.
//
//  Map PNGs were captured from the live site via Playwright with the GPS
//  dot and video hidden, preserving the CSS-styled land outlines exactly.
//

import SwiftUI

// MARK: - MinimapView

struct MinimapView: View {
    let lat: Double
    let lng: Double

    @State private var pulseScale: CGFloat = 1.0

    private var zone: MapZone { MapZone.forCoordinate(lat: lat, lng: lng) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Website-identical map background ──────────────────────
                Image(zone.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // ── GPS dot above the map ─────────────────────────────────
                let pos = dotPosition(in: geo.size)
                gpsMarker
                    .position(pos)
            }
        }
        .frame(width: zone.displaySize.width, height: zone.displaySize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 6)
        .accessibilityIdentifier("minimap")
        .accessibilityValue("\(lat),\(lng)")
        .onAppear { startPulse() }
        .onChange(of: lat) { startPulse() }
    }

    // MARK: GPS marker

    private var gpsMarker: some View {
        ZStack {
            // Pulse ring
            Circle()
                .fill(Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.45))
                .frame(width: 8, height: 8)
                .scaleEffect(pulseScale)
                .opacity(max(0, 1.0 - (pulseScale - 1.0) / 3.5))
            // White halo
            Circle()
                .strokeBorder(.white, lineWidth: 1.5)
                .frame(width: 10, height: 10)
            // Blue core
            Circle()
                .fill(Color(red: 0.29, green: 0.62, blue: 1.0))
                .frame(width: 7, height: 7)
                .shadow(color: Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.8), radius: 5)
        }
    }

    // MARK: Dot position (Web Mercator, matching MapKit rendering)

    private func dotPosition(in size: CGSize) -> CGPoint {
        let bounds = zone.bounds
        let x = ((lng - bounds.minLng) / (bounds.maxLng - bounds.minLng)) * size.width
        let y  = ((mercY(bounds.maxLat) - mercY(lat)) /
                  (mercY(bounds.maxLat) - mercY(bounds.minLat))) * size.height
        return CGPoint(
            x: max(8, min(size.width  - 8, x)),
            y: max(8, min(size.height - 8, y))
        )
    }

    private func mercY(_ latDeg: Double) -> Double {
        let r = latDeg * .pi / 180
        return log(tan(.pi / 4 + r / 2))
    }

    private func startPulse() {
        pulseScale = 1.0
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            pulseScale = 4.0
        }
    }
}

// MARK: - MapZone

enum MapZone: CaseIterable {
    case bay, ca, us, europe, world

    static func forCoordinate(lat: Double, lng: Double) -> MapZone {
        if lat >= 36.90 && lat <= 38.86 && lng >= -123.55 && lng <= -121.20 { return .bay    }
        if lat >= 32.50 && lat <= 42.00 && lng >= -124.50 && lng <= -114.00 { return .ca     }
        if lat >= 24.50 && lat <= 49.50 && lng >= -125.00 && lng <=  -66.00 { return .us     }
        if lat >= 34.00 && lat <= 57.00 && lng >=  -13.00 && lng <=   27.00 { return .europe }
        return .world
    }

    var imageName: String {
        switch self {
        case .bay:    return "map-bay"
        case .ca:     return "map-ca"
        case .us:     return "map-us"
        case .europe: return "map-europe"
        case .world:  return "map-world"
        }
    }

    /// Display size in SwiftUI points (matching website CSS pixel sizes)
    var displaySize: CGSize {
        switch self {
        case .bay:    return CGSize(width: 176, height: 112)
        case .ca:     return CGSize(width: 176, height: 112)
        case .us:     return CGSize(width: 176, height: 112)
        case .europe: return CGSize(width: 200, height: 110)
        case .world:  return CGSize(width: 214, height:  83)
        }
    }

    // Lat/lng bounds of the region shown by each map PNG —
    // used to project the dot onto the image coordinate space.
    var bounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) {
        switch self {
        case .bay:
            // projectBay: x = (lng - (-123.533665)) * 100, y = (38.864245 - lat) * 100
            // viewBox 0 0 232.5 196.8 → reverse: lat range 38.864245 - 196.8/100 = 36.896..38.864
            return (minLat: 36.90, maxLat: 38.87, minLng: -123.53, maxLng: -121.20)
        case .ca:
            // projectCA: x = (lng - (-124.5)) * 10, y = (42.0 - lat) * 10
            // viewBox 0 0 105 95 → lat 42 - 9.5 = 32.5..42, lng -124.5..-114
            return (minLat: 32.50, maxLat: 42.00, minLng: -124.50, maxLng: -114.00)
        case .us:
            // projectUS: x = (lng - (-125)) * 10, y = (49.5 - lat) * 10
            // viewBox 0 0 585 255 → lat 49.5 - 25.5 = 24..49.5, lng -125..-66.5
            return (minLat: 24.00, maxLat: 49.50, minLng: -125.00, maxLng:  -66.50)
        case .europe:
            // projectEurope uses same formula as world (x=lng+180, y=84-lat)
            // viewBox "167 28 40 22" → lng 167-180=-13..227-180=47, lat 84-28=56..84-50=34
            return (minLat: 34.00, maxLat: 56.00, minLng: -13.00, maxLng:  47.00)
        case .world:
            // projectWorld: x = lng + 180, y = 84 - lat
            // viewBox 0 0 360 139.6 → full equirectangular, lat 84-0=84..84-139.6=-55.6
            return (minLat: -55.60, maxLat: 84.00, minLng: -180.00, maxLng: 180.00)
        }
    }
}
