//  AerialPlayerView  (kept as WebView.swift to preserve the existing target membership)
//
//  Two-player crossfade engine for iOS. playerA and playerB are fixed instances
//  permanently bound to two AVPlayerViewController layers in the ZStack.
//  opacityA / opacityB drive SwiftUI crossfade animations without ever
//  swapping the player reference inside a live view controller.

import SwiftUI
import AVFoundation
import AVKit

// MARK: - Catalog

// A single video's metadata, decoded from the cloud manifest (catalog.json)
// or the bundled fallback below.
struct CatalogVideo: Decodable {
    let id: Int
    let caption: String
    let category: String
    let lat: Double?
    let lng: Double?
    let noPin: Bool?
}
private struct CatalogFile: Decodable { let videos: [CatalogVideo] }

// Runtime catalog. Starts from the bundled fallback so the app works offline
// and on first launch; Catalog.shared.load() replaces it with the cloud
// manifest (videos.pjloury.com/catalog.json) so new videos and categories
// appear with no app update.
final class Catalog {
    static let shared = Catalog()
    private(set) var videos: [CatalogVideo] = Catalog.fallback

    /// Distinct category ids in first-seen order (drives the switcher).
    var categories: [String] {
        var seen = Set<String>(); var out: [String] = []
        for v in videos where !seen.contains(v.category) {
            seen.insert(v.category); out.append(v.category)
        }
        return out
    }

    /// Video ids for a category (nil = all videos).
    func ids(in category: String?) -> [Int] {
        (category == nil ? videos : videos.filter { $0.category == category }).map(\.id)
    }

    func caption(forID id: Int) -> String { videos.first { $0.id == id }?.caption ?? "" }

    /// Fetch the cloud manifest; keep the current data on any failure.
    /// Returns true if the set of video ids changed.
    @discardableResult
    func load() async -> Bool {
        guard let url = URL(string: AerialCatalog.base + "/catalog.json") else { return false }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let file = try JSONDecoder().decode(CatalogFile.self, from: data)
            guard !file.videos.isEmpty else { return false }
            let changed = Set(file.videos.map(\.id)) != Set(videos.map(\.id))
            videos = file.videos
            return changed
        } catch {
            return false
        }
    }

    static let fallback: [CatalogVideo] = [
        CatalogVideo(id: 2, caption: "Good Morning Stanford", category: "cities", lat: 37.43, lng: -122.17, noPin: true),
        CatalogVideo(id: 3, caption: "Snowy Tahoe Treetops", category: "mountains", lat: 39.1, lng: -120.04, noPin: false),
        CatalogVideo(id: 4, caption: "Carmel Waves at Dusk", category: "coastal", lat: 36.55, lng: -121.92, noPin: false),
        CatalogVideo(id: 5, caption: "Financial District", category: "cities", lat: 37.72, lng: -122.42, noPin: false),
        CatalogVideo(id: 6, caption: "Heavenly Palo Alto", category: "cities", lat: 37.44, lng: -122.14, noPin: true),
        CatalogVideo(id: 7, caption: "Telegraph Hill", category: "cities", lat: 37.8, lng: -122.41, noPin: true),
        CatalogVideo(id: 8, caption: "Stanford Sunset", category: "cities", lat: 37.43, lng: -122.17, noPin: true),
        CatalogVideo(id: 10, caption: "Los Altos Hills", category: "cities", lat: 37.38, lng: -122.14, noPin: true),
        CatalogVideo(id: 11, caption: "Sterling Vineyard", category: "mountains", lat: 38.59, lng: -122.6, noPin: false),
        CatalogVideo(id: 12, caption: "Washington Square, North Beach", category: "cities", lat: 37.8, lng: -122.41, noPin: true),
        CatalogVideo(id: 13, caption: "New Office Site", category: "cities", lat: 37.4, lng: -122.11, noPin: true),
        CatalogVideo(id: 14, caption: "Bay to Breakers", category: "cities", lat: 37.77, lng: -122.45, noPin: true),
        CatalogVideo(id: 15, caption: "Wailea, Maui", category: "coastal", lat: 20.69, lng: -156.44, noPin: false),
        CatalogVideo(id: 16, caption: "Hvar, Croatia", category: "coastal", lat: 43.17, lng: 16.44, noPin: false),
        CatalogVideo(id: 17, caption: "Sather Tower, Berkeley", category: "cities", lat: 37.87, lng: -122.26, noPin: false),
        CatalogVideo(id: 18, caption: "Villa Collina", category: "cities", lat: 37.4, lng: -122.12, noPin: true),
        CatalogVideo(id: 19, caption: "Waves", category: "coastal", lat: 36.55, lng: -121.95, noPin: true),
        CatalogVideo(id: 20, caption: "Venice Canals", category: "cities", lat: 33.98, lng: -118.47, noPin: false),
        CatalogVideo(id: 21, caption: "University of San Francisco", category: "cities", lat: 37.78, lng: -122.45, noPin: true),
        CatalogVideo(id: 22, caption: "Old Valencia, Spain", category: "cities", lat: 39.47, lng: -0.38, noPin: false),
        CatalogVideo(id: 23, caption: "Arches National Park", category: "desert", lat: 38.73, lng: -109.59, noPin: false),
        CatalogVideo(id: 24, caption: "Mont Saint-Michel, France", category: "coastal", lat: 48.64, lng: -1.51, noPin: false),
        CatalogVideo(id: 26, caption: "Salzburg, Austria", category: "cities", lat: 47.8, lng: 13.04, noPin: false),
        CatalogVideo(id: 27, caption: "Park City Morning, Utah", category: "mountains", lat: 40.65, lng: -111.5, noPin: false),
        CatalogVideo(id: 29, caption: "Canyonlands National Park", category: "desert", lat: 38.33, lng: -109.88, noPin: false),
        CatalogVideo(id: 30, caption: "Vogelsang Lake, Yosemite", category: "mountains", lat: 37.78, lng: -119.35, noPin: false),
        CatalogVideo(id: 31, caption: "Austria", category: "mountains", lat: 47.5, lng: 13.5, noPin: false),
        CatalogVideo(id: 32, caption: "Almaden Green", category: "cities", lat: 37.24, lng: -121.86, noPin: true),
        CatalogVideo(id: 33, caption: "Mont Saint-Michel", category: "coastal", lat: 48.64, lng: -1.51, noPin: false),
        CatalogVideo(id: 34, caption: "SF Lunar New Year", category: "cities", lat: 37.79, lng: -122.41, noPin: true),
        CatalogVideo(id: 35, caption: "Big Sur Hills", category: "coastal", lat: 36.27, lng: -121.81, noPin: false),
        CatalogVideo(id: 36, caption: "Fort Funston", category: "coastal", lat: 37.72, lng: -122.5, noPin: false),
        CatalogVideo(id: 37, caption: "Fort Funston & Golden Gate", category: "coastal", lat: 37.72, lng: -122.5, noPin: false),
        CatalogVideo(id: 39, caption: "Mont Saint-Michel", category: "coastal", lat: 48.64, lng: -1.51, noPin: false),
        CatalogVideo(id: 40, caption: "Neuschwanstein Castle, Germany", category: "mountains", lat: 47.56, lng: 10.75, noPin: false),
        CatalogVideo(id: 41, caption: "Park City, Utah", category: "mountains", lat: 40.65, lng: -111.5, noPin: false),
        CatalogVideo(id: 42, caption: "Golden Gate Bridge", category: "cities", lat: 37.82, lng: -122.48, noPin: true),
        CatalogVideo(id: 43, caption: "Balearic Islands, Spain", category: "coastal", lat: 39.57, lng: 2.65, noPin: false),
        CatalogVideo(id: 44, caption: "Mont Saint-Michel", category: "coastal", lat: 48.64, lng: -1.51, noPin: false),
        CatalogVideo(id: 45, caption: "Drifting Away", category: "coastal", lat: -50.34, lng: -72.27, noPin: false),
        CatalogVideo(id: 46, caption: "Laguna de los Tres, Patagonia", category: "mountains", lat: -49.33, lng: -72.99, noPin: false),
        CatalogVideo(id: 47, caption: "Canyonlands", category: "desert", lat: 38.33, lng: -109.88, noPin: false),
        CatalogVideo(id: 48, caption: "Ka\\u02bbanapali Surf, Maui", category: "coastal", lat: 20.93, lng: -156.69, noPin: false),
        CatalogVideo(id: 49, caption: "Copacabana, Brazil", category: "coastal", lat: -22.97, lng: -43.18, noPin: false),
        CatalogVideo(id: 50, caption: "Palma, Mallorca", category: "cities", lat: 39.57, lng: 2.65, noPin: false),
        CatalogVideo(id: 51, caption: "Fuschl am See, Austria", category: "mountains", lat: 47.8, lng: 13.29, noPin: false),
        CatalogVideo(id: 52, caption: "Moab, Utah", category: "desert", lat: 38.57, lng: -109.55, noPin: false),
        CatalogVideo(id: 53, caption: "Carmel-by-the-Sea", category: "coastal", lat: 36.55, lng: -121.92, noPin: false),
        CatalogVideo(id: 54, caption: "Garrapata State Park", category: "coastal", lat: 36.47, lng: -121.92, noPin: false),
        CatalogVideo(id: 55, caption: "Arches National Park", category: "desert", lat: 38.73, lng: -109.59, noPin: false),
        CatalogVideo(id: 56, caption: "Wailea South, Maui", category: "coastal", lat: 20.67, lng: -156.44, noPin: false),
        CatalogVideo(id: 57, caption: "Red Rocks", category: "desert", lat: 39.67, lng: -105.2, noPin: false),
        CatalogVideo(id: 58, caption: "Alviso Salt Marsh", category: "desert", lat: 37.43, lng: -121.97, noPin: true),
        CatalogVideo(id: 59, caption: "UC Berkeley Campus", category: "cities", lat: 37.87, lng: -122.26, noPin: true),
        CatalogVideo(id: 60, caption: "SF Embarcadero", category: "cities", lat: 37.85, lng: -122.38, noPin: false),
        CatalogVideo(id: 61, caption: "Stanford Main Quad", category: "cities", lat: 37.43, lng: -122.17, noPin: false),
        CatalogVideo(id: 62, caption: "Sather Tower, Berkeley", category: "cities", lat: 37.87, lng: -122.26, noPin: true),
        CatalogVideo(id: 63, caption: "Albanian Alps", category: "mountains", lat: 42.41, lng: 19.79, noPin: true),
        CatalogVideo(id: 64, caption: "Kotor, Montenegro", category: "coastal", lat: 42.43, lng: 18.77, noPin: false),
        CatalogVideo(id: 65, caption: "Deer Valley, Utah", category: "mountains", lat: 40.63, lng: -111.48, noPin: false),
        CatalogVideo(id: 66, caption: "Denver, Colorado", category: "cities", lat: 39.74, lng: -104.98, noPin: false),
        CatalogVideo(id: 67, caption: "Dubrovnik, Croatia", category: "coastal", lat: 42.65, lng: 18.09, noPin: false),
        CatalogVideo(id: 68, caption: "Grand Baths, Budapest", category: "cities", lat: 47.51, lng: 19.05, noPin: false),
        CatalogVideo(id: 69, caption: "Hoʻokipa Beach, Maui", category: "coastal", lat: 20.94, lng: -156.34, noPin: false),
        CatalogVideo(id: 70, caption: "Bay of Kotor, Montenegro", category: "coastal", lat: 42.43, lng: 18.77, noPin: true),
        CatalogVideo(id: 71, caption: "Lands End, San Francisco", category: "coastal", lat: 37.78, lng: -122.51, noPin: true),
        CatalogVideo(id: 72, caption: "Maui Lava Coast", category: "coastal", lat: 20.8, lng: -156.5, noPin: true),
        CatalogVideo(id: 73, caption: "Ocean Beach, San Francisco", category: "coastal", lat: 37.76, lng: -122.51, noPin: false),
        CatalogVideo(id: 74, caption: "Old Town Dubrovnik", category: "cities", lat: 42.65, lng: 18.09, noPin: true),
        CatalogVideo(id: 75, caption: "Port Novi, Montenegro", category: "coastal", lat: 42.45, lng: 18.68, noPin: false),
        CatalogVideo(id: 76, caption: "Schönbrunn Palace, Vienna", category: "cities", lat: 48.18, lng: 16.31, noPin: false),
        CatalogVideo(id: 77, caption: "Theth, Albania at Sunset", category: "mountains", lat: 42.41, lng: 19.79, noPin: true),
        CatalogVideo(id: 78, caption: "Theth Summit, Albania", category: "mountains", lat: 42.45, lng: 19.85, noPin: false),
        CatalogVideo(id: 79, caption: "Theth Sunrise, Albania", category: "mountains", lat: 42.41, lng: 19.79, noPin: true),
        CatalogVideo(id: 80, caption: "Tivat, Montenegro", category: "coastal", lat: 42.44, lng: 18.7, noPin: true),
        CatalogVideo(id: 81, caption: "Walled City of Dubrovnik", category: "cities", lat: 42.64, lng: 18.11, noPin: true),
        CatalogVideo(id: 82, caption: "West Maui Coastline", category: "coastal", lat: 20.88, lng: -156.5, noPin: false),
        CatalogVideo(id: 83, caption: "Yosemite Falls", category: "mountains", lat: 37.754, lng: -119.597, noPin: false),
        CatalogVideo(id: 84, caption: "Yosemite Valley at Twilight", category: "mountains", lat: 37.745, lng: -119.587, noPin: true),
        CatalogVideo(id: 85, caption: "Yosemite Valley", category: "mountains", lat: 37.745, lng: -119.587, noPin: false),    ]
}

enum AerialCatalog {
    static let base = "https://videos.pjloury.com"

    static func mobileURL(_ num: Int) -> URL {
        URL(string: String(format: "%@/video-%02d-mobile.mp4", base, num))!
    }

    /// Caption for a mobile URL, resolved through the live catalog.
    static func caption(for url: URL) -> String {
        for v in Catalog.shared.videos where mobileURL(v.id) == url { return v.caption }
        return ""
    }
}

// MARK: - Playback mode

struct PlaybackMode: Identifiable, Equatable {
    let id: String   // "shuffle" or a category id
    var label: String {
        id == "shuffle" ? "Shuffle All" : id.prefix(1).uppercased() + id.dropFirst()
    }
    static let shuffle = PlaybackMode(id: "shuffle")

    /// Shuffled ids for this mode, resolved through the live catalog.
    var clipNumbers: [Int] {
        Catalog.shared.ids(in: id == "shuffle" ? nil : id).shuffled()
    }

    /// Shuffle + one entry per category present in the catalog (data-driven).
    static var all: [PlaybackMode] {
        [.shuffle] + Catalog.shared.categories.map { PlaybackMode(id: $0) }
    }
}

// MARK: - Model

final class AerialPlayerModel: NSObject, ObservableObject {

    // Two fixed players — each permanently bound to one ZStack layer.
    let playerA = AVPlayer()
    let playerB = AVPlayer()
    // Which player is currently the "front" (visible) one.
    private var isFrontA = true
    private var frontPlayer: AVPlayer { isFrontA ? playerA : playerB }
    private var backPlayer:  AVPlayer { isFrontA ? playerB : playerA }

    @Published private(set) var currentTitle = ""
    @Published private(set) var mode: PlaybackMode = .shuffle
    // Data-driven switcher: Shuffle + one entry per category in the catalog.
    @Published private(set) var availableModes: [PlaybackMode] = PlaybackMode.all
    @Published private(set) var leftFlash  = false
    @Published private(set) var rightFlash = false
    // Layer opacities — SwiftUI animates these for the crossfade.
    @Published private(set) var opacityA: Double = 1.0
    @Published private(set) var opacityB: Double = 0.0
    @Published private(set) var playbackProgress: Double = 0.0
    /// False during a crossfade — hides the progress bar while it resets to 0.
    @Published private(set) var progressVisible: Bool = true

    private var playlist: [URL] = []
    private var activeURLs: Set<URL> = []
    private var currentIndex = 0
    private var isCrossfading = false
    private var timeObserver: Any?
    // The exact player the observer was attached to. AVFoundation raises a
    // fatal exception if you remove a time observer from a *different* player
    // than the one it was added to — and frontPlayer flips on every crossfade,
    // so we must remember the owner rather than assume it's the current front.
    private var timeObserverOwner: AVPlayer?

    static let manualCrossfadeDuration: TimeInterval = 1.5
    static let autoCrossfadeDuration:   TimeInterval = 4.0

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .moviePlayback, policy: .longFormVideo)
        for p in [playerA, playerB] {
            p.isMuted = true
            p.allowsExternalPlayback = true
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)

        setMode(.shuffle)

        // Pull the cloud manifest; if it brings new videos, refresh the
        // switcher and rebuild the current playlist. Falls back silently to
        // the bundled catalog on any failure.
        Task { [weak self] in
            let changed = await Catalog.shared.load()
            await MainActor.run {
                guard let self else { return }
                self.availableModes = PlaybackMode.all
                if changed { self.setMode(self.mode) }
            }
        }
    }

    // MARK: Public

    func setMode(_ newMode: PlaybackMode) {
        let isInitial = playlist.isEmpty
        // Ignore a switch while a crossfade is already running (mirrors skip*())
        // so transitions never stack. The initial setup always proceeds.
        guard isInitial || !isCrossfading else { return }

        mode = newMode
        let urls = newMode.clipNumbers.map(AerialCatalog.mobileURL)
        guard !urls.isEmpty else { return }
        playlist = urls
        activeURLs = Set(urls)
        currentIndex = 0

        if isInitial {
            // First run: nothing is playing yet, so start instantly.
            isFrontA = true
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { opacityA = 1; opacityB = 0 }

            frontPlayer.replaceCurrentItem(with: AVPlayerItem(url: urls[0]))
            frontPlayer.seek(to: .zero)
            frontPlayer.play()
            updateTitle(for: urls[0])
            startTimeObserver()

            if urls.count > 1 {
                backPlayer.replaceCurrentItem(with: AVPlayerItem(url: urls[1]))
            }
        } else {
            // Switching category while playing: dissolve from the current clip
            // into the new category's first clip, same as a manual skip.
            crossfade(to: urls[0], duration: Self.manualCrossfadeDuration)
        }
    }

    func skipForward() {
        guard !isCrossfading, !playlist.isEmpty else { return }
        currentIndex = (currentIndex + 1) % playlist.count
        flashRight()
        crossfade(to: playlist[currentIndex], duration: Self.manualCrossfadeDuration)
    }

    func skipBackward() {
        guard !isCrossfading, !playlist.isEmpty else { return }
        currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        flashLeft()
        crossfade(to: playlist[currentIndex], duration: Self.manualCrossfadeDuration)
    }

    // MARK: Private

    private func crossfade(to url: URL, duration: TimeInterval) {
        isCrossfading = true
        removeTimeObserver()

        // Fade bar out before resetting — mirrors tvOS overlayVisible pattern.
        withAnimation(.easeInOut(duration: 0.3)) { progressVisible = false }

        backPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        backPlayer.seek(to: .zero)
        backPlayer.play()
        updateTitle(for: url)

        withAnimation(.easeInOut(duration: duration)) {
            if isFrontA { opacityA = 0; opacityB = 1 }
            else        { opacityB = 0; opacityA = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            self.frontPlayer.pause()
            self.frontPlayer.replaceCurrentItem(with: nil)
            self.isFrontA.toggle()
            self.isCrossfading = false
            self.playbackProgress = 0
            self.startTimeObserver()
            // Fade bar back in after reset.
            withAnimation(.easeInOut(duration: 0.3)) { self.progressVisible = true }

            // Preload the clip after the one we just switched to.
            let nextIdx = (self.currentIndex + 1) % self.playlist.count
            self.backPlayer.replaceCurrentItem(with: AVPlayerItem(url: self.playlist[nextIdx]))
        }
    }

    private func updateTitle(for url: URL) {
        let title = AerialCatalog.caption(for: url)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.4)) { self.currentTitle = title }
        }
    }

    private func startTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        let observed = frontPlayer
        timeObserverOwner = observed
        timeObserver = observed.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let item = observed.currentItem else { return }
            let dur = item.duration.seconds
            guard dur > 0, !dur.isNaN, !dur.isInfinite else { return }
            self.playbackProgress = min(time.seconds / dur, 1.0)
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver {
            // Remove from the player it was added to — never assume it's the
            // current frontPlayer, which may have flipped during a crossfade.
            (timeObserverOwner ?? frontPlayer).removeTimeObserver(obs)
            timeObserver = nil
            timeObserverOwner = nil
        }
    }

    private func flashLeft() {
        leftFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { self.leftFlash = false }
    }

    private func flashRight() {
        rightFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { self.rightFlash = false }
    }

    @objc private func appWillEnterForeground() {
        frontPlayer.play()
    }

    @objc private func itemDidEnd(_ note: Notification) {
        guard let finished = note.object as? AVPlayerItem,
              let asset = finished.asset as? AVURLAsset,
              activeURLs.contains(asset.url),
              frontPlayer.currentItem === finished,
              !isCrossfading else { return }
        currentIndex = (currentIndex + 1) % playlist.count
        crossfade(to: playlist[currentIndex], duration: Self.autoCrossfadeDuration)
    }

    deinit {
        removeTimeObserver()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Nav arrow (mirrors tvOS PlayerOverlayView style)

struct IOSNavArrowView: View {
    let pointsLeft: Bool
    let lit: Bool

    @State private var opacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                ZStack {
                    IOSTaperedArrowShape(pointsLeft: pointsLeft).fill(.ultraThinMaterial).opacity(0.55)
                    IOSTaperedArrowShape(pointsLeft: pointsLeft).fill(.white.opacity(0.06))
                    IOSTaperedArrowShape(pointsLeft: pointsLeft).stroke(.white.opacity(0.18), lineWidth: 1)
                    Image(systemName: pointsLeft ? "chevron.left" : "chevron.right")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .offset(x: pointsLeft ? 3 : -3)
                }
                .frame(width: 48, height: geo.size.height * 0.38)
                .opacity(opacity)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: pointsLeft ? .leading : .trailing)
        }
        .onChange(of: lit) { newValue in
            guard newValue else { return }
            withAnimation(.easeOut(duration: 0.24)) { opacity = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.32) {
                withAnimation(.easeOut(duration: 1.08)) { opacity = 0.0 }
            }
        }
    }
}

struct IOSTaperedArrowShape: Shape {
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

// MARK: - AirPlay button

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

// MARK: - Player view

struct AerialPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
