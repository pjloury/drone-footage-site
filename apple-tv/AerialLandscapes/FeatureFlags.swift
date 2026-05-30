//
//  FeatureFlags.swift
//  AerialLandscapes
//
//  Created by PJ Loury on 7/6/25.
//

import Foundation

struct FeatureFlags {
    /// When true, include 4 short test videos in the catalog
    static let enableTestVideos = false

    /// When true, retrieve remote videos from S3 (legacy — R2 catalog is now the default)
    static let enableRemoteVideos = false

    /// When true, generate thumbnails from local video files
    static let generateThumbnails = false
}
