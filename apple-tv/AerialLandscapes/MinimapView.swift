//
//  MinimapView.swift
//  AerialLandscapes
//
//  Frosted-glass minimap in the bottom-right corner, matching the website.
//  Uses MapKit with a zone-aware region (bay / ca / us / europe / world)
//  derived from the same lat/lng boundary rules as the web app.
//

import SwiftUI
import MapKit

struct MinimapView: View {
    let lat: Double
    let lng: Double

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var zone: MapZone { MapZone.forCoordinate(lat: lat, lng: lng) }

    var body: some View {
        Map(position: .constant(MapCameraPosition.region(zone.region(for: coordinate)))) {
            Annotation("", coordinate: coordinate, anchor: .center) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.29, green: 0.62, blue: 1.0))
                        .frame(width: 10, height: 10)
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: 10, height: 10)
                    // Pulse ring
                    Circle()
                        .fill(Color(red: 0.29, green: 0.62, blue: 1.0).opacity(0.5))
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false),
                                   value: pulseScale)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .disabled(true)
        .allowsHitTesting(false)
        .frame(width: 200, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .onAppear { pulseScale = 1.8; pulseOpacity = 0 }
    }

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
}

// MARK: - Map zone (mirrors the website's five-tier cascade)

enum MapZone {
    case bay, ca, us, europe, world

    static func forCoordinate(lat: Double, lng: Double) -> MapZone {
        if lat >= 36.90 && lat <= 38.86 && lng >= -123.55 && lng <= -121.20 { return .bay }
        if lat >= 32.50 && lat <= 42.00 && lng >= -124.50 && lng <= -114.00 { return .ca  }
        if lat >= 24.50 && lat <= 49.50 && lng >= -125.00 && lng <=  -66.00 { return .us  }
        if lat >= 34.00 && lat <= 57.00 && lng >=  -13.00 && lng <=   27.00 { return .europe }
        return .world
    }

    // Centre of each zoomed region (not the clip location, matching web behaviour)
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

    func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: span)
    }
}
