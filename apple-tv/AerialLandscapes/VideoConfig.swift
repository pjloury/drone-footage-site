// VideoConfig.swift
//
// `shared` now returns the full drone-footage R2 catalog (80+ clips).
// The legacy local-bundle video arrays (domesticVideos, internationalVideos)
// are kept intact below for reference; set useR2Catalog = false to restore them.

private let R2_BASE = "https://videos.pjloury.com"

private func r2(_ num: Int, _ title: String, _ geozone: String) -> Video {
    let file = "video-\(String(format: "%02d", num))"
    return Video(
        id: file,
        displayTitle: title,
        geozone: geozone,
        remoteVideoPath: "\(R2_BASE)/\(file).mp4",
        remoteThumbnailPath: "\(R2_BASE)/\(file)-poster.jpg",
        localVideoPath: nil,
        localThumbnailPath: nil,
        isSelected: true
    )
}

struct VideoConfig {
    let videos: [VideoMetadata]

    // ── R2 catalog ──────────────────────────────────────────────────────────
    // All 80+ clips from drones.pjloury.com, streamed directly from
    // Cloudflare R2 (videos.pjloury.com).  Geozones become section headers
    // in the MoreVideosView browse grid.

    static let r2Videos: [Video] = [
        // Bay Area
        r2(2,  "Good Morning Stanford",          "Bay Area"),
        r2(5,  "Financial District",             "Bay Area"),
        r2(6,  "Heavenly Palo Alto",             "Bay Area"),
        r2(7,  "Telegraph Hill",                 "Bay Area"),
        r2(8,  "Stanford Sunset",                "Bay Area"),
        r2(10, "Los Altos Hills",                "Bay Area"),
        r2(12, "Washington Square, North Beach", "Bay Area"),
        r2(13, "New Office Site",                "Bay Area"),
        r2(14, "Bay to Breakers",                "Bay Area"),
        r2(17, "Sather Tower, Berkeley",         "Bay Area"),
        r2(18, "Villa Collina",                  "Bay Area"),
        r2(21, "University of San Francisco",    "Bay Area"),
        r2(34, "SF Lunar New Year",              "Bay Area"),
        r2(36, "Fort Funston",                   "Bay Area"),
        r2(37, "Fort Funston & Golden Gate",     "Bay Area"),
        r2(42, "Golden Gate Bridge",             "Bay Area"),
        r2(58, "Alviso Salt Marsh",              "Bay Area"),
        r2(59, "UC Berkeley Campus",             "Bay Area"),
        r2(60, "SF Embarcadero",                 "Bay Area"),
        r2(61, "Stanford Main Quad",             "Bay Area"),
        r2(62, "Sather Tower, Berkeley",         "Bay Area"),
        r2(71, "Lands End, San Francisco",       "Bay Area"),
        r2(73, "Ocean Beach, San Francisco",     "Bay Area"),

        // California
        r2(3,  "Snowy Tahoe Treetops",           "California"),
        r2(4,  "Carmel Waves at Dusk",           "California"),
        r2(11, "Sterling Vineyard",              "California"),
        r2(19, "Waves",                          "California"),
        r2(32, "Almaden Green",                  "California"),
        r2(35, "Big Sur Hills",                  "California"),
        r2(53, "Carmel-by-the-Sea",              "California"),
        r2(54, "Garrapata State Park",           "California"),
        r2(30, "Vogelsang Lake, Yosemite",       "California"),
        r2(83, "Yosemite Falls",                 "California"),
        r2(84, "Yosemite Valley at Twilight",    "California"),
        r2(85, "Yosemite Valley",                "California"),

        // Hawaii
        r2(15, "Wailea, Maui",                   "Hawaii"),
        r2(48, "Ka\u{02BB}anapali Surf, Maui",   "Hawaii"),
        r2(56, "Wailea South, Maui",             "Hawaii"),
        r2(69, "Ho\u{02BB}okipa Beach, Maui",    "Hawaii"),
        r2(72, "Maui Lava Coast",                "Hawaii"),
        r2(82, "West Maui Coastline",            "Hawaii"),

        // United States
        r2(20, "Venice Canals",                  "United States"),
        r2(23, "Arches National Park",           "United States"),
        r2(27, "Park City Morning, Utah",        "United States"),
        r2(29, "Canyonlands National Park",      "United States"),
        r2(41, "Park City, Utah",                "United States"),
        r2(45, "Drifting Away",                  "United States"),
        r2(47, "Canyonlands",                    "United States"),
        r2(52, "Moab, Utah",                     "United States"),
        r2(55, "Arches National Park",           "United States"),
        r2(57, "Red Rocks",                      "United States"),
        r2(65, "Deer Valley, Utah",              "United States"),
        r2(66, "Denver, Colorado",               "United States"),

        // Europe
        r2(16, "Hvar, Croatia",                  "Europe"),
        r2(22, "Old Valencia, Spain",            "Europe"),
        r2(24, "Mont Saint-Michel, France",      "Europe"),
        r2(26, "Salzburg, Austria",              "Europe"),
        r2(31, "Austria",                        "Europe"),
        r2(33, "Mont Saint-Michel",              "Europe"),
        r2(39, "Mont Saint-Michel",              "Europe"),
        r2(40, "Neuschwanstein Castle, Germany", "Europe"),
        r2(43, "Balearic Islands, Spain",        "Europe"),
        r2(44, "Mont Saint-Michel",              "Europe"),
        r2(50, "Palma, Mallorca",                "Europe"),
        r2(51, "Fuschl am See, Austria",         "Europe"),
        r2(63, "Albanian Alps",                  "Europe"),
        r2(64, "Kotor, Montenegro",              "Europe"),
        r2(67, "Dubrovnik, Croatia",             "Europe"),
        r2(68, "Grand Baths, Budapest",          "Europe"),
        r2(70, "Bay of Kotor, Montenegro",       "Europe"),
        r2(74, "Old Town Dubrovnik",             "Europe"),
        r2(75, "Port Novi, Montenegro",          "Europe"),
        r2(76, "Sch\u{00F6}nbrunn Palace, Vienna", "Europe"),
        r2(77, "Theth, Albania at Sunset",       "Europe"),
        r2(78, "Theth Summit, Albania",          "Europe"),
        r2(79, "Theth Sunrise, Albania",         "Europe"),
        r2(80, "Tivat, Montenegro",              "Europe"),
        r2(81, "Walled City of Dubrovnik",       "Europe"),

        // International
        r2(46, "Laguna de los Tres, Patagonia",  "International"),
        r2(49, "Copacabana, Brazil",             "International"),
    ]

    // ── shared: returns R2 catalog ───────────────────────────────────────────
    static var allVideos: [Video] { r2Videos }

    // ── Legacy local-bundle infrastructure (kept for reference) ──────────────

    static let domesticVideos = [
        VideoMetadata(uuid: "FF001", filename: "Fort Funston",  displayTitle: "Fort Funston",        geozone: "domestic"),
        VideoMetadata(uuid: "WV001", filename: "Waves",         displayTitle: "Waves",               geozone: "domestic"),
        VideoMetadata(uuid: "RR001", filename: "Red Rocks",     displayTitle: "Red Rocks, Nevada",   geozone: "domestic"),
        VideoMetadata(uuid: "SF001", filename: "Salt Flats",    displayTitle: "Salt Flats",          geozone: "domestic"),
    ]

    static let internationalVideos = [
        VideoMetadata(uuid: "BA001",  filename: "BalearicIslands",    displayTitle: "Balearic Islands, Spain",     geozone: "international"),
        VideoMetadata(uuid: "FAS001", filename: "FuschlAmSee",        displayTitle: "Fuschl am See, Austria",      geozone: "international"),
        VideoMetadata(uuid: "HC001",  filename: "HvarCroatia",        displayTitle: "Hvar, Croatia",               geozone: "international"),
        VideoMetadata(uuid: "LDT01",  filename: "Laguna de los Tres", displayTitle: "Laguna de los Tres, Patagonia", geozone: "international"),
    ]

    static let testVideos = [
        VideoMetadata(uuid: "TA001", filename: "TestAlps", displayTitle: "Fuschl am See",  geozone: "international"),
        VideoMetadata(uuid: "TH001", filename: "TestHvar", displayTitle: "Hvar, Croatia",  geozone: "international"),
        VideoMetadata(uuid: "TC001", filename: "TestCopa", displayTitle: "Copacabana",     geozone: "international"),
    ]

    static let shared: VideoConfig = VideoConfig(videos: domesticVideos + internationalVideos)
}

struct VideoMetadata {
    let uuid: String
    let filename: String
    let displayTitle: String
    let geozone: String
}
