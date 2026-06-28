// VideoConfig.swift — R2 catalog with section + lat/lng for minimap

import Foundation

private let R2 = "https://videos.pjloury.com"

private func r2(_ num: Int, _ title: String, _ section: String,
                _ lat: Double? = nil, _ lng: Double? = nil) -> Video {
    let file = String(format: "video-%02d", num)
    return Video(
        id: file, displayTitle: title, geozone: section,
        remoteVideoPath:     "\(R2)/\(file).mp4",
        remoteThumbnailPath: "\(R2)/\(file)-poster.jpg",
        localVideoPath: nil, localThumbnailPath: nil,
        isSelected: true, lat: lat, lng: lng
    )
}

struct VideoConfig {

    static let allVideos: [Video] = [
        // Cities
        r2(2,  "Good Morning Stanford",           "cities",   37.43, -122.17),
        r2(5,  "Financial District",              "cities",   37.72, -122.42),
        r2(6,  "Heavenly Palo Alto",              "cities",   37.44, -122.14),
        r2(7,  "Telegraph Hill",                  "cities",   37.80, -122.41),
        r2(8,  "Stanford Sunset",                 "cities",   37.43, -122.17),
        r2(10, "Los Altos Hills",                 "cities",   37.38, -122.14),
        r2(12, "Washington Square, North Beach",  "cities",   37.80, -122.41),
        r2(13, "New Office Site",                 "cities",   37.40, -122.11),
        r2(14, "Bay to Breakers",                 "cities",   37.77, -122.45),
        r2(17, "Sather Tower, Berkeley",          "cities",   37.87, -122.26),
        r2(18, "Villa Collina",                   "cities",   37.40, -122.12),
        r2(20, "Venice Canals",                   "cities",   33.98, -118.47),
        r2(21, "University of San Francisco",     "cities",   37.78, -122.45),
        r2(22, "Old Valencia, Spain",             "cities",   39.47,   -0.38),
        r2(26, "Salzburg, Austria",               "cities",   47.80,   13.04),
        r2(32, "Almaden Green",                   "cities",   37.24, -121.86),
        r2(34, "SF Lunar New Year",               "cities",   37.79, -122.41),
        r2(42, "Golden Gate Bridge",              "cities",   37.82, -122.48),
        r2(50, "Palma, Mallorca",                 "cities",   39.57,    2.65),
        r2(59, "UC Berkeley Campus",              "cities",   37.87, -122.26),
        r2(60, "SF Embarcadero",                  "cities",   37.85, -122.38),
        r2(61, "Stanford Main Quad",              "cities",   37.43, -122.17),
        r2(62, "Sather Tower, Berkeley",          "cities",   37.87, -122.26),
        r2(66, "Denver, Colorado",                "cities",   39.74, -104.98),
        r2(68, "Grand Baths, Budapest",           "cities",   47.51,   19.05),
        r2(74, "Old Town Dubrovnik",              "cities",   42.65,   18.09),
        r2(76, "Sch\u{00F6}nbrunn Palace, Vienna","cities",   48.18,   16.31),
        r2(81, "Walled City of Dubrovnik",        "cities",   42.64,   18.11),

        // Coastal
        r2(4,  "Carmel Waves at Dusk",            "coastal",  36.55, -121.92),
        r2(15, "Wailea, Maui",                    "coastal",  20.69, -156.44),
        r2(16, "Hvar, Croatia",                   "coastal",  43.17,   16.44),
        r2(19, "Waves",                           "coastal",  36.55, -121.95),
        r2(24, "Mont Saint-Michel, France",       "coastal",  48.64,   -1.51),
        r2(33, "Mont Saint-Michel",               "coastal",  48.64,   -1.51),
        r2(35, "Big Sur Hills",                   "coastal",  36.27, -121.81),
        r2(36, "Fort Funston",                    "coastal",  37.72, -122.50),
        r2(37, "Fort Funston & Golden Gate",      "coastal",  37.72, -122.50),
        r2(39, "Mont Saint-Michel",               "coastal",  48.64,   -1.51),
        r2(43, "Balearic Islands, Spain",         "coastal",  39.57,    2.65),
        r2(44, "Mont Saint-Michel",               "coastal",  48.64,   -1.51),
        r2(45, "Drifting Away",                   "coastal", -50.34,  -72.27),  // near El Calafate, Patagonia, Argentina
        r2(48, "Ka\u{02BB}anapali Surf, Maui",    "coastal",  20.93, -156.69),
        r2(49, "Copacabana, Brazil",              "coastal", -22.97,  -43.18),
        r2(53, "Carmel-by-the-Sea",               "coastal",  36.55, -121.92),
        r2(54, "Garrapata State Park",            "coastal",  36.47, -121.92),
        r2(56, "Wailea South, Maui",              "coastal",  20.67, -156.44),
        r2(64, "Kotor, Montenegro",               "coastal",  42.43,   18.77),
        r2(67, "Dubrovnik, Croatia",              "coastal",  42.65,   18.09),
        r2(69, "Ho\u{02BB}okipa Beach, Maui",     "coastal",  20.94, -156.34),
        r2(70, "Bay of Kotor, Montenegro",        "coastal",  42.43,   18.77),
        r2(71, "Lands End, San Francisco",        "coastal",  37.78, -122.51),
        r2(72, "Maui Lava Coast",                 "coastal",  20.60, -156.40),  // La Perouse Bay / south Maui lava coast
        r2(73, "Ocean Beach, San Francisco",      "coastal",  37.76, -122.51),
        r2(75, "Port Novi, Montenegro",           "coastal",  42.45,   18.68),
        r2(80, "Tivat, Montenegro",               "coastal",  42.44,   18.70),
        r2(82, "West Maui Coastline",             "coastal",  20.88, -156.50),

        // Mountains
        r2(3,  "Snowy Tahoe Treetops",            "mountains",39.10, -120.04),
        r2(11, "Sterling Vineyard",               "mountains",38.59, -122.60),
        r2(27, "Park City Morning, Utah",         "mountains",40.65, -111.50),
        r2(30, "Vogelsang Lake, Yosemite",        "mountains",37.78, -119.35),
        r2(31, "Austria",                         "mountains",47.50,   13.50),
        r2(40, "Neuschwanstein Castle, Germany",  "mountains",47.56,   10.75),
        r2(41, "Park City, Utah",                 "mountains",40.65, -111.50),
        r2(46, "Laguna de los Tres, Patagonia",   "mountains",-49.33, -72.99),
        r2(51, "Fuschl am See, Austria",          "mountains",47.80,   13.29),
        r2(63, "Albanian Alps",                   "mountains",42.41,   19.79),
        r2(65, "Deer Valley, Utah",               "mountains",40.63, -111.48),
        r2(77, "Theth, Albania at Sunset",        "mountains",42.41,   19.79),
        r2(78, "Theth Summit, Albania",           "mountains",42.45,   19.85),
        r2(79, "Theth Sunrise, Albania",          "mountains",42.41,   19.79),
        r2(83, "Yosemite Falls",                  "mountains",37.754,-119.597),
        r2(84, "Yosemite Valley at Twilight",     "mountains",37.745,-119.587),
        r2(85, "Yosemite Valley",                 "mountains",37.745,-119.587),

        // Desert
        r2(23, "Arches National Park",            "desert",   38.73, -109.59),
        r2(29, "Canyonlands National Park",       "desert",   38.33, -109.88),
        r2(47, "Canyonlands",                     "desert",   38.33, -109.88),
        r2(52, "Moab, Utah",                      "desert",   38.57, -109.55),
        r2(55, "Arches National Park",            "desert",   38.73, -109.59),
        r2(57, "Red Rocks",                       "desert",   39.67, -105.20),
        r2(58, "Alviso Salt Marsh",               "desert",   37.43, -121.97),
    ]

    // Legacy local-bundle infrastructure (kept so VideoPlayerModel still compiles)
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
    let videos: [VideoMetadata]
    static let shared = VideoConfig(videos: domesticVideos + internationalVideos)
}

struct VideoMetadata {
    let uuid: String
    let filename: String
    let displayTitle: String
    let geozone: String
}
