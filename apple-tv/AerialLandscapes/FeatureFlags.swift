//
//  FeatureFlags.swift
//  AerialLandscapes
//
//  Created by PJ Loury on 7/6/25.
//

import Foundation

struct FeatureFlags {
    /// When true, show the drones.pjloury.com WebView experience instead of
    /// the native Aerial Landscapes player.  Set to false to fall back to
    /// the original tab-based interface with local + S3 video browsing.
    static let useWebExperience = true

    /// When true, include 4 short videos for testing purposes
    static let enableTestVideos = false

    /// When true, retrieve remote videos from S3
    static let enableRemoteVideos = false

    /// When true, generate thumbnails from video files
    static let generateThumbnails = false
}
