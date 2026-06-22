//  AerialPlayerView  (kept as WebView.swift to preserve the existing target membership)
//
//  Minimal native iOS player: one AVQueuePlayer streams the R2 mobile catalog
//  in shuffled order and loops forever with hard cuts. No crossfade, no
//  controls — the lightweight native equivalent of the web/tvOS aerial feel,
//  without WKWebView's video-freeze problems. Publishes the current clip's
//  title for the bottom-left caption overlay.

import SwiftUI
import AVFoundation
import AVKit

/// R2 catalog — number + title mirror VideoConfig.allVideos. Mobile encodes
/// (1080p, fixed 2s keyframes) are streamed for phone/cellular reliability.
enum AerialCatalog {
    static let base = "https://videos.pjloury.com"

    static let clips: [(num: Int, title: String)] = [
        (2, "Good Morning Stanford"), (5, "Financial District"),
        (6, "Heavenly Palo Alto"), (7, "Telegraph Hill"), (8, "Stanford Sunset"),
        (10, "Los Altos Hills"), (12, "Washington Square, North Beach"),
        (13, "New Office Site"), (14, "Bay to Breakers"),
        (17, "Sather Tower, Berkeley"), (18, "Villa Collina"),
        (20, "Venice Canals"), (21, "University of San Francisco"),
        (22, "Old Valencia, Spain"), (26, "Salzburg, Austria"),
        (32, "Almaden Green"), (34, "SF Lunar New Year"),
        (42, "Golden Gate Bridge"), (50, "Palma, Mallorca"),
        (59, "UC Berkeley Campus"), (60, "SF Embarcadero"),
        (61, "Stanford Main Quad"), (62, "Sather Tower, Berkeley"),
        (66, "Denver, Colorado"), (68, "Grand Baths, Budapest"),
        (74, "Old Town Dubrovnik"), (76, "Schönbrunn Palace, Vienna"),
        (81, "Walled City of Dubrovnik"), (4, "Carmel Waves at Dusk"),
        (15, "Wailea, Maui"), (16, "Hvar, Croatia"), (19, "Waves"),
        (24, "Mont Saint-Michel, France"), (33, "Mont Saint-Michel"),
        (35, "Big Sur Hills"), (36, "Fort Funston"),
        (37, "Fort Funston & Golden Gate"), (39, "Mont Saint-Michel"),
        (43, "Balearic Islands, Spain"), (44, "Mont Saint-Michel"),
        (45, "Drifting Away"), (48, "Kaʻanapali Surf, Maui"),
        (49, "Copacabana, Brazil"), (53, "Carmel-by-the-Sea"),
        (54, "Garrapata State Park"), (56, "Wailea South, Maui"),
        (64, "Kotor, Montenegro"), (67, "Dubrovnik, Croatia"),
        (69, "Hoʻokipa Beach, Maui"), (70, "Bay of Kotor, Montenegro"),
        (71, "Lands End, San Francisco"), (72, "Maui Lava Coast"),
        (73, "Ocean Beach, San Francisco"), (75, "Port Novi, Montenegro"),
        (80, "Tivat, Montenegro"), (82, "West Maui Coastline"),
        (3, "Snowy Tahoe Treetops"), (11, "Sterling Vineyard"),
        (27, "Park City Morning, Utah"), (30, "Vogelsang Lake, Yosemite"),
        (31, "Austria"), (40, "Neuschwanstein Castle, Germany"),
        (41, "Park City, Utah"), (46, "Laguna de los Tres, Patagonia"),
        (51, "Fuschl am See, Austria"), (63, "Albanian Alps"),
        (65, "Deer Valley, Utah"), (77, "Theth, Albania at Sunset"),
        (78, "Theth Summit, Albania"), (79, "Theth Sunrise, Albania"),
        (83, "Yosemite Falls"), (84, "Yosemite Valley at Twilight"),
        (85, "Yosemite Valley"), (23, "Arches National Park"),
        (29, "Canyonlands National Park"), (47, "Canyonlands"),
        (52, "Moab, Utah"), (55, "Arches National Park"),
        (57, "Red Rocks"), (58, "Alviso Salt Marsh"),
    ]

    static func mobileURL(_ num: Int) -> URL {
        URL(string: String(format: "%@/video-%02d-mobile.mp4", base, num))!
    }

    /// Map from the streamed URL back to its display title for caption lookup.
    static let titlesByURL: [URL: String] = Dictionary(
        clips.map { (mobileURL($0.num), $0.title) }, uniquingKeysWith: { a, _ in a })

    /// Clip numbers per section (mirrors VideoConfig grouping).
    static let sectionNumbers: [String: Set<Int>] = [
        "cities":    [2, 5, 6, 7, 8, 10, 12, 13, 14, 17, 18, 20, 21, 22, 26, 32,
                      34, 42, 50, 59, 60, 61, 62, 66, 68, 74, 76, 81],
        "coastal":   [4, 15, 16, 19, 24, 33, 35, 36, 37, 39, 43, 44, 45, 48, 49,
                      53, 54, 56, 64, 67, 69, 70, 71, 72, 73, 75, 80, 82],
        "mountains": [3, 11, 27, 30, 31, 40, 41, 46, 51, 63, 65, 77, 78, 79, 83,
                      84, 85],
        "desert":    [23, 29, 47, 52, 55, 57, 58],
    ]
}

/// Playback modes — "Shuffle All" plus one per section, mirroring the web app.
enum PlaybackMode: String, CaseIterable, Identifiable {
    case shuffle, cities, coastal, mountains, desert
    var id: String { rawValue }

    var label: String {
        switch self {
        case .shuffle:   return "Shuffle All"
        case .cities:    return "Cities"
        case .coastal:   return "Coastal"
        case .mountains: return "Mountains"
        case .desert:    return "Desert"
        }
    }

    /// Shuffled clip numbers for this mode.
    var clipNumbers: [Int] {
        let nums: [Int]
        if self == .shuffle {
            nums = AerialCatalog.clips.map(\.num)
        } else {
            nums = AerialCatalog.clips.map(\.num)
                .filter { AerialCatalog.sectionNumbers[rawValue]?.contains($0) ?? false }
        }
        return nums.shuffled()
    }
}

/// Owns the AVQueuePlayer and keeps it playing forever: when a clip finishes,
/// its URL is re-appended to the tail so the queue never drains. Publishes the
/// current clip's title via KVO on `currentItem`.
final class AerialPlayerModel: NSObject, ObservableObject {
    let player = AVQueuePlayer()
    @Published private(set) var currentTitle = ""
    @Published private(set) var mode: PlaybackMode = .shuffle
    /// True when AirPlay-eligible external routes are detected nearby — drives
    /// the reveal of the AirPlay button.
    @Published private(set) var airplayAvailable = false

    private let routeDetector = AVRouteDetector()
    /// URLs valid for the active mode — guards itemDidEnd against re-appending
    /// a stale clip from a previous mode after the queue is rebuilt.
    private var activeURLs: Set<URL> = []

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player.isMuted = true
        player.allowsExternalPlayback = true
        player.actionAtItemEnd = .advance

        // Manual (Obj-C) KVO throughout — Swift's typed observe(_:options:)
        // traps on these AVFoundation properties in the simulator. Read the
        // live value inside observeValue instead.
        //
        // currentItem can be nil/NSNull while the queue is empty.
        player.addObserver(self, forKeyPath: "currentItem", options: [.initial, .new], context: nil)

        // Watch for nearby AirPlay devices; reveal the button only when present.
        routeDetector.isRouteDetectionEnabled = true
        routeDetector.addObserver(self, forKeyPath: "multipleRoutesDetected", options: [.initial, .new], context: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime, object: nil)

        setMode(.shuffle)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                              change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case "currentItem":
            let title = (player.currentItem?.asset as? AVURLAsset)
                .flatMap { AerialCatalog.titlesByURL[$0.url] } ?? ""
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.4)) { self.currentTitle = title }
            }
        case "multipleRoutesDetected":
            let available = routeDetector.multipleRoutesDetected
            DispatchQueue.main.async { self.airplayAvailable = available }
        default:
            break
        }
    }

    /// Rebuild the queue for the given mode and start playing.
    func setMode(_ newMode: PlaybackMode) {
        mode = newMode
        let urls = newMode.clipNumbers.map(AerialCatalog.mobileURL)
        activeURLs = Set(urls)
        player.removeAllItems()
        for url in urls { player.insert(AVPlayerItem(url: url), after: nil) }
        player.play()
    }

    @objc private func itemDidEnd(_ note: Notification) {
        guard let finished = note.object as? AVPlayerItem,
              let asset = finished.asset as? AVURLAsset,
              activeURLs.contains(asset.url) else { return }
        // Re-append the finished clip so playback loops indefinitely.
        player.insert(AVPlayerItem(url: asset.url), after: nil)
    }

    deinit {
        player.removeObserver(self, forKeyPath: "currentItem")
        routeDetector.removeObserver(self, forKeyPath: "multipleRoutesDetected")
        routeDetector.isRouteDetectionEnabled = false
        NotificationCenter.default.removeObserver(self)
    }
}

/// SwiftUI wrapper around the system AirPlay route picker. Tapping it shows the
/// AirPlay device list and routes playback to the chosen device.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(red: 0.30, green: 0.70, blue: 1.0, alpha: 1.0)
        v.prioritizesVideoDevices = true
        return v
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Bridges AVPlayerViewController (chrome-free, aspect-fill) into SwiftUI.
struct AerialPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}
