//
//  aerial_landscapesTests.swift
//  AerialLandscapesTests
//

import XCTest
@testable import AerialLandscapes

final class AerialLandscapesTests: XCTestCase {

    func testVideoConfigHasVideos() {
        XCTAssertFalse(VideoConfig.allVideos.isEmpty, "allVideos should not be empty")
        XCTAssertEqual(VideoConfig.allVideos.count, 80, "Should have 80 videos")
    }

    func testAllVideosHaveR2URLs() {
        for video in VideoConfig.allVideos {
            XCTAssertNotNil(video.remoteVideoURL, "Video \(video.id) should have a URL")
            XCTAssertTrue(video.remoteVideoURL!.absoluteString.hasPrefix("https://videos.pjloury.com"),
                          "Video \(video.id) should use R2 URL")
        }
    }

    func testVideoSectionsAreValid() {
        let validSections = Set(["cities", "coastal", "mountains", "desert"])
        for video in VideoConfig.allVideos {
            XCTAssertTrue(validSections.contains(video.geozone),
                          "Video \(video.id) has unknown section '\(video.geozone)'")
        }
    }

    func testAllActiveVideosHaveCoordinates() {
        let missing = VideoConfig.allVideos.filter { $0.lat == nil || $0.lng == nil }
        XCTAssertTrue(missing.isEmpty,
                      "Videos missing coords: \(missing.map { $0.id }.joined(separator: ", "))")
    }

    func testMapZoneClassification() {
        // Bay Area
        XCTAssertEqual(MapZone.forCoordinate(lat: 37.85, lng: -122.38), .bay)   // SF Embarcadero
        // California
        XCTAssertEqual(MapZone.forCoordinate(lat: 36.55, lng: -121.92), .ca)    // Carmel
        // US
        XCTAssertEqual(MapZone.forCoordinate(lat: 38.73, lng: -109.59), .us)    // Arches
        // Europe
        XCTAssertEqual(MapZone.forCoordinate(lat: 47.56, lng: 10.75),   .europe) // Neuschwanstein
        // World
        XCTAssertEqual(MapZone.forCoordinate(lat: -49.33, lng: -72.99), .world)  // Patagonia
        XCTAssertEqual(MapZone.forCoordinate(lat: 20.69,  lng: -156.44),.world)  // Maui
    }

    func testStreamingPlayerModelSectionsCount() {
        XCTAssertEqual(StreamingPlayerModel.sections.count, 4)
        let ids = StreamingPlayerModel.sections.map { $0.id }
        XCTAssertTrue(ids.contains("cities"))
        XCTAssertTrue(ids.contains("coastal"))
        XCTAssertTrue(ids.contains("mountains"))
        XCTAssertTrue(ids.contains("desert"))
    }

    func testStreamingPlayerModelLoadSection() {
        let model = StreamingPlayerModel()
        model.loadSection("coastal")
        XCTAssertEqual(model.activeSection, "coastal")
        XCTAssertFalse(model.currentTitle.isEmpty, "Should have a title after loading coastal")

        model.loadSection(nil)
        XCTAssertNil(model.activeSection)
    }
}
