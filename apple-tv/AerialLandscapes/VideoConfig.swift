// VideoConfig.swift
//
// allVideos: full R2 catalog with sections matching drones.pjloury.com VIDEO_META
//   "cities" / "coastal" / "mountains" / "desert"
//
// Legacy local-bundle arrays (domesticVideos, internationalVideos) kept for reference.

import Foundation

private let R2 = "https://videos.pjloury.com"

private func r2(_ num: Int, _ title: String, _ section: String) -> Video {
    let file = String(format: "video-%02d", num)
    return Video(
        id: file,
        displayTitle: title,
        geozone: section,
        remoteVideoPath:      "\(R2)/\(file).mp4",
        remoteThumbnailPath:  "\(R2)/\(file)-poster.jpg",
        localVideoPath:       nil,
        localThumbnailPath:   nil,
        isSelected:           true
    )
}

struct VideoConfig {

    // ── R2 catalog — sections match the website exactly ──────────────────────

    static let allVideos: [Video] = [
        // Cities
        r2(2,  "Good Morning Stanford",           "cities"),
        r2(5,  "Financial District",              "cities"),
        r2(6,  "Heavenly Palo Alto",              "cities"),
        r2(7,  "Telegraph Hill",                  "cities"),
        r2(8,  "Stanford Sunset",                 "cities"),
        r2(10, "Los Altos Hills",                 "cities"),
        r2(12, "Washington Square, North Beach",  "cities"),
        r2(13, "New Office Site",                 "cities"),
        r2(14, "Bay to Breakers",                 "cities"),
        r2(17, "Sather Tower, Berkeley",          "cities"),
        r2(18, "Villa Collina",                   "cities"),
        r2(20, "Venice Canals",                   "cities"),
        r2(21, "University of San Francisco",     "cities"),
        r2(22, "Old Valencia, Spain",             "cities"),
        r2(26, "Salzburg, Austria",               "cities"),
        r2(32, "Almaden Green",                   "cities"),
        r2(34, "SF Lunar New Year",               "cities"),
        r2(42, "Golden Gate Bridge",              "cities"),
        r2(50, "Palma, Mallorca",                 "cities"),
        r2(59, "UC Berkeley Campus",              "cities"),
        r2(60, "SF Embarcadero",                  "cities"),
        r2(61, "Stanford Main Quad",              "cities"),
        r2(62, "Sather Tower, Berkeley",          "cities"),
        r2(66, "Denver, Colorado",                "cities"),
        r2(68, "Grand Baths, Budapest",           "cities"),
        r2(74, "Old Town Dubrovnik",              "cities"),
        r2(76, "Sch\u{00F6}nbrunn Palace, Vienna","cities"),
        r2(81, "Walled City of Dubrovnik",        "cities"),

        // Coastal
        r2(4,  "Carmel Waves at Dusk",            "coastal"),
        r2(15, "Wailea, Maui",                    "coastal"),
        r2(16, "Hvar, Croatia",                   "coastal"),
        r2(19, "Waves",                           "coastal"),
        r2(24, "Mont Saint-Michel, France",       "coastal"),
        r2(33, "Mont Saint-Michel",               "coastal"),
        r2(35, "Big Sur Hills",                   "coastal"),
        r2(36, "Fort Funston",                    "coastal"),
        r2(37, "Fort Funston & Golden Gate",      "coastal"),
        r2(39, "Mont Saint-Michel",               "coastal"),
        r2(43, "Balearic Islands, Spain",         "coastal"),
        r2(44, "Mont Saint-Michel",               "coastal"),
        r2(45, "Drifting Away",                   "coastal"),
        r2(48, "Ka\u{02BB}anapali Surf, Maui",    "coastal"),
        r2(49, "Copacabana, Brazil",              "coastal"),
        r2(53, "Carmel-by-the-Sea",               "coastal"),
        r2(54, "Garrapata State Park",            "coastal"),
        r2(56, "Wailea South, Maui",              "coastal"),
        r2(64, "Kotor, Montenegro",               "coastal"),
        r2(67, "Dubrovnik, Croatia",              "coastal"),
        r2(69, "Ho\u{02BB}okipa Beach, Maui",     "coastal"),
        r2(70, "Bay of Kotor, Montenegro",        "coastal"),
        r2(71, "Lands End, San Francisco",        "coastal"),
        r2(72, "Maui Lava Coast",                 "coastal"),
        r2(73, "Ocean Beach, San Francisco",      "coastal"),
        r2(75, "Port Novi, Montenegro",           "coastal"),
        r2(80, "Tivat, Montenegro",               "coastal"),
        r2(82, "West Maui Coastline",             "coastal"),

        // Mountains
        r2(3,  "Snowy Tahoe Treetops",            "mountains"),
        r2(11, "Sterling Vineyard",               "mountains"),
        r2(27, "Park City Morning, Utah",         "mountains"),
        r2(30, "Vogelsang Lake, Yosemite",        "mountains"),
        r2(31, "Austria",                         "mountains"),
        r2(40, "Neuschwanstein Castle, Germany",  "mountains"),
        r2(41, "Park City, Utah",                 "mountains"),
        r2(46, "Laguna de los Tres, Patagonia",   "mountains"),
        r2(51, "Fuschl am See, Austria",          "mountains"),
        r2(63, "Albanian Alps",                   "mountains"),
        r2(65, "Deer Valley, Utah",               "mountains"),
        r2(77, "Theth, Albania at Sunset",        "mountains"),
        r2(78, "Theth Summit, Albania",           "mountains"),
        r2(79, "Theth Sunrise, Albania",          "mountains"),
        r2(83, "Yosemite Falls",                  "mountains"),
        r2(84, "Yosemite Valley at Twilight",     "mountains"),
        r2(85, "Yosemite Valley",                 "mountains"),

        // Desert
        r2(23, "Arches National Park",            "desert"),
        r2(29, "Canyonlands National Park",       "desert"),
        r2(47, "Canyonlands",                     "desert"),
        r2(52, "Moab, Utah",                      "desert"),
        r2(55, "Arches National Park",            "desert"),
        r2(57, "Red Rocks",                       "desert"),
        r2(58, "Alviso Salt Marsh",               "desert"),
    ]

    // ── Legacy local-bundle infrastructure (kept for reference) ──────────────

    static let domesticVideos = [
        VideoMetadata(uuid: "FF001", filename: "Fort Funston", displayTitle: "Fort Funston",      geozone: "coastal"),
        VideoMetadata(uuid: "WV001", filename: "Waves",        displayTitle: "Waves",             geozone: "coastal"),
        VideoMetadata(uuid: "RR001", filename: "Red Rocks",    displayTitle: "Red Rocks, Nevada", geozone: "desert"),
        VideoMetadata(uuid: "SF001", filename: "Salt Flats",   displayTitle: "Salt Flats",        geozone: "desert"),
    ]

    static let internationalVideos = [
        VideoMetadata(uuid: "BA001",  filename: "BalearicIslands",    displayTitle: "Balearic Islands, Spain",      geozone: "coastal"),
        VideoMetadata(uuid: "FAS001", filename: "FuschlAmSee",        displayTitle: "Fuschl am See, Austria",       geozone: "mountains"),
        VideoMetadata(uuid: "HC001",  filename: "HvarCroatia",        displayTitle: "Hvar, Croatia",                geozone: "coastal"),
        VideoMetadata(uuid: "LDT01",  filename: "Laguna de los Tres", displayTitle: "Laguna de los Tres, Patagonia",geozone: "mountains"),
    ]

    static let testVideos = [
        VideoMetadata(uuid: "TA001", filename: "TestAlps", displayTitle: "Fuschl am See", geozone: "mountains"),
        VideoMetadata(uuid: "TH001", filename: "TestHvar", displayTitle: "Hvar, Croatia", geozone: "coastal"),
        VideoMetadata(uuid: "TC001", filename: "TestCopa", displayTitle: "Copacabana",    geozone: "coastal"),
    ]

    // Retained so VideoPlayerModel still compiles
    let videos: [VideoMetadata]
    static let shared = VideoConfig(videos: domesticVideos + internationalVideos)
}

struct VideoMetadata {
    let uuid: String
    let filename: String
    let displayTitle: String
    let geozone: String
}
