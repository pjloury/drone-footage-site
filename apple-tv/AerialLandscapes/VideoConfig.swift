struct VideoConfig {
    let videos: [VideoMetadata]
    
    static let domesticVideos = [
        VideoMetadata(
            uuid: "FF001",
            filename: "Fort Funston",
            displayTitle: "Fort Funston",
            geozone: "domestic"
        ),
        VideoMetadata(
            uuid: "WV001",
            filename: "Waves",
            displayTitle: "Waves",
            geozone: "domestic"
        ),
        VideoMetadata(
            uuid: "RR001",
            filename: "Red Rocks",
            displayTitle: "Red Rocks, Nevada",
            geozone: "domestic"
        ),
        VideoMetadata(
            uuid: "SF001",
            filename: "Salt Flats",
            displayTitle: "Salt Flats",
            geozone: "domestic"
        )
        //,
        //        VideoMetadata(
        //            uuid: "NMC01",
        //            filename: "NorthernMarinCoast",
        //            displayTitle: "Northern Marin Coast",
        //            geozone: "domestic"
        //        ),
        //        VideoMetadata(
        //            uuid: "SQ001",
        //            filename: "Stanford Main Quad",
        //            displayTitle: "Stanford Main Quad",
        //            geozone: "domestic"
        //        ),
        //        VideoMetadata(
        //            uuid: "ST001",
        //            filename: "Sather Tower",
        //            displayTitle: "Sather Tower",
        //            geozone: "domestic"
        //        )
    ]

    static let internationalVideos = [
        VideoMetadata(
            uuid: "BA001",
            filename: "BalearicIslands",
            displayTitle: "Balearic Islands, Spain",
            geozone: "international"
        ),
        VideoMetadata(
            uuid: "FAS001",
            filename: "FuschlAmSee",
            displayTitle: "Fuschl am See, Austria",
            geozone: "international"
        ),
        VideoMetadata(
            uuid: "HC001",
            filename: "HvarCroatia",
            displayTitle: "Hvar, Croatia",
            geozone: "international"
        ),
        VideoMetadata(
            uuid: "LDT01",
            filename: "Laguna de los Tres",
            displayTitle: "Laguna de los Tres, Patagonia",
            geozone: "international"
        ),
    ]
    
    static let testVideos = [
        VideoMetadata(
            uuid: "TA001",
            filename: "TestAlps",
            displayTitle: "Fuschl am See",
            geozone: "international"
        ),
        VideoMetadata(
            uuid: "TH001",
            filename: "TestHvar",
            displayTitle: "Hvar, Croatia",
            geozone: "international"
        ),
        VideoMetadata(
            uuid: "TC001",
            filename: "TestCopa",
            displayTitle: "Copacabana",
            geozone: "international"
        ),
        // Add more test videos as needed
    ]
    
    static let shared: VideoConfig = {
        let videos = FeatureFlags.enableTestVideos ? (domesticVideos + internationalVideos + testVideos) :
         (domesticVideos + internationalVideos)
        return VideoConfig(videos: videos)
    }()
}

struct VideoMetadata {
    let uuid: String
    let filename: String
    let displayTitle: String
    let geozone: String
} 
