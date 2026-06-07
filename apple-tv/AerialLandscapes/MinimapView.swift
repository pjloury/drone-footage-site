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

    private var zone: MapZone { MapZone.forCoordinate(lat: lat, lng: lng) }

    // Load PNGs from bundle — Image("name") only reads asset catalogs,
    // not raw resources bundled via FileSystemSynchronizedRootGroup.
    //   mapImage  — white continent fill + outlines, transparent water
    //   maskImage — solid silhouette of the land, used to clip the
    //               frosted-glass plate so only land is frosted (water clear)
    @State private var mapImage:  UIImage? = nil
    @State private var maskImage: UIImage? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Land plate, clipped to the land silhouette ────────────
                // Mirrors the website's masked minimap visually, but does NOT
                // use a live backdrop blur (`.ultraThinMaterial`). That blur
                // samples + Gaussian-blurs the 4K AVPlayerLayer behind it on
                // EVERY frame, which on tvOS competes with the hardware video
                // decoder for GPU/memory bandwidth and stalls it — the video
                // freezes (currentTime stops) while compositor-thread
                // animations like the pulse rings keep going. Regression
                // introduced 2026-06-05 (e30ddc8) and removed here.
                //
                // A flat translucent plate is visually ~identical at minimap
                // size and does zero per-frame video readback.
                if let mask = maskImage {
                    Rectangle()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(
                            Image(uiImage: mask)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                        )
                }

                // ── Continent fill (13% white) + outlines (58% white) ─────
                if let img = mapImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                // ── GPS dot above the map ─────────────────────────────────
                let pos = dotPosition(in: geo.size)
                gpsMarker
                    .position(pos)
            }
        }
        .frame(width: zone.displaySize.width, height: zone.displaySize.height)
        .accessibilityIdentifier("minimap")
        .accessibilityValue("\(lat),\(lng)")
        .onAppear { loadMapImage() }
        .onChange(of: lat) { loadMapImage() }
    }

    // MARK: GPS marker

    private var gpsMarker: some View {
        ZStack {
            // Three staggered pulse rings — luxuriously slow, wide diffusion
            PulseRing(startDelay: 0.0)
            PulseRing(startDelay: 4.0 / 3.0)   // 1.33 s
            PulseRing(startDelay: 4.0 * 2 / 3)  // 2.67 s
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

    // MARK: Dot position
    //
    // Mirrors the website EXACTLY. On the web, the dot SVG and the map SVG
    // share a viewBox and are both centered in the plate at a fixed
    // per-zone width (CSS: `position:absolute; top/left:50%;
    // translate(-50%,-50%); width:<mapRenderWidth>; height:auto`). The dot
    // is placed at the projected viewBox coordinate, so it lands on the
    // same pixel as the landmass below.
    //
    // The tvOS PNGs are captures of that same plate (map centered at
    // `mapRenderWidth`), displayed 1:1 in the displaySize frame — so we
    // reproduce the identical transform here:
    //   1. project (lat,lng) → viewBox coords (equirectangular, per web)
    //   2. scale the viewBox to `mapRenderWidth`, height auto
    //   3. center that rendered rect in the frame
    //   4. place the dot at (projected − viewBoxOrigin) × scale + centerOffset
    private func dotPosition(in size: CGSize) -> CGPoint {
        let vb = zone.viewBox
        let p  = zone.project(lat: lat, lng: lng)
        let scale     = zone.mapRenderWidth / vb.w
        let renderedW = vb.w * scale
        let renderedH = vb.h * scale
        let offX = (size.width  - renderedW) / 2
        let offY = (size.height - renderedH) / 2
        return CGPoint(x: offX + (p.x - vb.x) * scale,
                       y: offY + (p.y - vb.y) * scale)
    }

    private func loadMapImage() {
        mapImage  = loadBundlePNG(zone.imageName)
        maskImage = loadBundlePNG(zone.imageName + "-mask")
    }

    private func loadBundlePNG(_ name: String) -> UIImage? {
        if let path = Bundle.main.path(forResource: name, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        // Fallback: try UIImage(named:) in case Xcode bundled it differently
        return UIImage(named: name)
    }

}

// MARK: - PulseRing
//
// One expanding ring of the GPS diffusion animation.
// Three instances with staggered startDelays create an evenly-spaced ripple.
//
// Cycle (4 s):
//   0 ms  — instant reset to scale 1.0, opacity 0.5 (via disablesAnimations)
//   16 ms — easeOut expansion begins: scale 1 → 6, opacity 0.5 → 0
//   4 s   — ring is fully invisible; next cycle starts
//
// The reset always happens while the ring is at opacity 0, so the
// snap from scale 6 → 1 is invisible — no flicker.

private struct PulseRing: View {
    let startDelay: Double

    static let cycleDuration: Double  = 4.0
    static let maxScale:      CGFloat = 6.0

    @State private var scale:   CGFloat = 1.0
    @State private var opacity: Double  = 0.5

    var body: some View {
        Circle()
            .fill(Color(red: 0.29, green: 0.62, blue: 1.0))
            .frame(width: 10, height: 10)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                    cycle()
                }
            }
    }

    private func cycle() {
        // 1. Instant reset — ring snaps to small/visible with no animation
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            scale   = 1.0
            opacity = 0.5
        }
        // 2. One render frame later, begin the slow easeOut expansion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            withAnimation(.easeOut(duration: Self.cycleDuration)) {
                scale   = Self.maxScale
                opacity = 0.0
            }
            // 3. At the end of the cycle, start over
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.cycleDuration) {
                cycle()
            }
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

    // SVG viewBox (origin x, origin y, width, height) — MUST match the
    // corresponding maps/<zone>.svg viewBox, since the PNGs are rendered
    // from those SVGs and the dot is projected into the same space.
    var viewBox: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        switch self {
        case .bay:    return (0,   0,   232.5, 196.8)
        case .ca:     return (0,   0,   105,    95)
        case .us:     return (0,   0,   585,   255)
        case .europe: return (167, 28,   40,    22)
        case .world:  return (0,   0,   360,   139.6)
        }
    }

    // Rendered width of the map SVG inside the plate, matching the website
    // CSS (`#map-<zone> { width: … }`). The SVG is centered in displaySize
    // with height:auto, so this width + the viewBox aspect fix the scale
    // and the centering offset.
    var mapRenderWidth: CGFloat {
        switch self {
        case .bay:    return 132
        case .ca:     return 106
        case .us:     return 176
        case .europe: return 200
        case .world:  return 214
        }
    }

    // Equirectangular projection from (lat,lng) → SVG viewBox coords,
    // identical to the website's project<Zone>() functions. All maps are
    // plate-carrée (linear in lat), NOT Mercator.
    func project(lat: Double, lng: Double) -> (x: CGFloat, y: CGFloat) {
        switch self {
        case .bay:    return (CGFloat((lng + 123.533665) * 100.0), CGFloat((38.864245 - lat) * 100.0))
        case .ca:     return (CGFloat((lng + 124.5)       *  10.0), CGFloat((42.0       - lat) *  10.0))
        case .us:     return (CGFloat((lng + 125.0)       *  10.0), CGFloat((49.5       - lat) *  10.0))
        case .europe: return (CGFloat(lng + 180.0),                 CGFloat(84.0 - lat))
        case .world:  return (CGFloat(lng + 180.0),                 CGFloat(84.0 - lat))
        }
    }
}
