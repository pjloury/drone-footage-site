//
//  MinimapView.swift
//  AerialLandscapes
//
//  Liquid-glass minimap matching the website's aesthetic:
//  — Dark MapKit tiles at low opacity (geography just readable)
//  — ultraThinMaterial frost layer over the top
//  — Blue GPS dot + pulsing ring drawn ABOVE the frost via equirectangular projection
//  — Gradient border simulating the "inset highlight" of liquid glass
//

import SwiftUI
import MapKit

// MARK: - MinimapView

struct MinimapView: View {
    let lat: Double
    let lng: Double

    @State private var pulseScale: CGFloat = 1.0

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    private var zone: MapZone { MapZone.forCoordinate(lat: lat, lng: lng) }
    private var cameraPosition: MapCameraPosition {
        .region(MKCoordinateRegion(center: zone.center, span: zone.span))
    }

    // Convert lat/lng → pixel position within the minimap frame
    private func dotPosition(in size: CGSize) -> CGPoint {
        let region = zone.region
        let minLat = region.center.latitude  - region.span.latitudeDelta  / 2
        let maxLat = region.center.latitude  + region.span.latitudeDelta  / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2

        let x = ((lng - minLng) / (maxLng - minLng)) * size.width
        let y = ((maxLat - lat) / (maxLat - minLat)) * size.height  // north = top
        return CGPoint(
            x: max(10, min(size.width  - 10, x)),
            y: max(10, min(size.height - 10, y))
        )
    }

    var body: some View {
        ZStack {
            // ── Layer 1: dark MapKit tiles (just enough to read geography) ──
            Map(position: .constant(cameraPosition))
                .colorScheme(.dark)
                .saturation(0.08)          // near-grayscale
                .contrast(0.85)
                .opacity(0.45)             // subtle, not dominant
                .allowsHitTesting(false)
                .disabled(true)

            // ── Layer 2: liquid-glass frost ────────────────────────────────
            // ultraThinMaterial applies backdrop blur (matches website's
            // backdrop-filter: blur(22px)) and tints with system vibrancy
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.72)

            // ── Layer 3: GPS dot above the frost ──────────────────────────
            GeometryReader { geo in
                let pos = dotPosition(in: geo.size)

                ZStack {
                    // Outer pulse ring
                    Circle()
                        .fill(Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.45))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseScale)
                        .opacity(max(0, 1.0 - (pulseScale - 1.0) / 3.0))

                    // White halo
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .frame(width: 10, height: 10)

                    // Blue core dot
                    Circle()
                        .fill(Color(red: 0.29, green: 0.62, blue: 1.0))
                        .frame(width: 7, height: 7)
                        .shadow(color: Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.7),
                                radius: 4)
                }
                .position(pos)
            }
        }
        .frame(width: 200, height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Gradient border — top-left highlight fading to subtle bottom-right
        // exactly matching the website's inset box-shadow + border look
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.12),
                            .white.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
        .onAppear {
            withAnimation(
                .easeOut(duration: 1.8).repeatForever(autoreverses: false)
            ) { pulseScale = 4.0 }
        }
        // Reset pulse when the clip changes (new coordinate)
        .onChange(of: lat) { pulseScale = 1.0; withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulseScale = 4.0 } }
    }
}

// MARK: - MapZone

enum MapZone {
    case bay, ca, us, europe, world

    static func forCoordinate(lat: Double, lng: Double) -> MapZone {
        if lat >= 36.90 && lat <= 38.86 && lng >= -123.55 && lng <= -121.20 { return .bay }
        if lat >= 32.50 && lat <= 42.00 && lng >= -124.50 && lng <= -114.00 { return .ca  }
        if lat >= 24.50 && lat <= 49.50 && lng >= -125.00 && lng <=  -66.00 { return .us  }
        if lat >= 34.00 && lat <= 57.00 && lng >=  -13.00 && lng <=   27.00 { return .europe }
        return .world
    }

    var center: CLLocationCoordinate2D {
        switch self {
        case .bay:    return CLLocationCoordinate2D(latitude:  37.80, longitude: -122.30)
        case .ca:     return CLLocationCoordinate2D(latitude:  37.50, longitude: -119.50)
        case .us:     return CLLocationCoordinate2D(latitude:  38.50, longitude:  -97.00)
        case .europe: return CLLocationCoordinate2D(latitude:  48.00, longitude:   13.00)
        case .world:  return CLLocationCoordinate2D(latitude:  20.00, longitude:    0.00)
        }
    }

    var span: MKCoordinateSpan {
        switch self {
        case .bay:    return MKCoordinateSpan(latitudeDelta:  2.0, longitudeDelta:  3.0)
        case .ca:     return MKCoordinateSpan(latitudeDelta: 11.0, longitudeDelta: 12.0)
        case .us:     return MKCoordinateSpan(latitudeDelta: 30.0, longitudeDelta: 65.0)
        case .europe: return MKCoordinateSpan(latitudeDelta: 25.0, longitudeDelta: 40.0)
        case .world:  return MKCoordinateSpan(latitudeDelta:150.0, longitudeDelta:340.0)
        }
    }

    // Region centred on the zone (not the clip) — matches web behaviour where
    // the map never re-centres on the exact clip location
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: span)
    }
}
