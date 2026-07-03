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

    static let titlesByURL: [URL: String] = Dictionary(
        clips.map { (mobileURL($0.num), $0.title) }, uniquingKeysWith: { a, _ in a })

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

// MARK: - Playback mode

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
    }

    // MARK: Public

    func setMode(_ newMode: PlaybackMode) {
        mode = newMode
        let urls = newMode.clipNumbers.map(AerialCatalog.mobileURL)
        playlist = urls
        activeURLs = Set(urls)
        currentIndex = 0
        isCrossfading = false
        isFrontA = true

        // Instantly reset opacities without animation.
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
        let title = AerialCatalog.titlesByURL[url] ?? ""
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
