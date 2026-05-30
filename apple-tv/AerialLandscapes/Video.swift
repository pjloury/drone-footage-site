import Foundation
import SwiftUI
import AVFoundation

struct Video: Identifiable, Codable {
    // Identity
    let id: String           // e.g., "FF001" from config or derived from S3 filename
    let displayTitle: String
    let geozone: String     // "domestic" or "international"
    
    // Paths
    let remoteVideoPath: String?     // Make optional
    let remoteThumbnailPath: String? // Make optional
    var localVideoPath: String?     // e.g., "Videos/FF001.mp4"
    var localThumbnailPath: String?  // Add this property
    
    // State
    var isSelected: Bool 
    
    // Computed properties
    var isLocal: Bool { localVideoPath != nil }
    
    // Initialize with lowercase geozone
    init(id: String, displayTitle: String, geozone: String, remoteVideoPath: String?, remoteThumbnailPath: String?, localVideoPath: String?, localThumbnailPath: String?, isSelected: Bool) {
        self.id = id
        self.displayTitle = displayTitle
        self.geozone = geozone.lowercased()
        self.remoteVideoPath = remoteVideoPath
        self.remoteThumbnailPath = remoteThumbnailPath
        self.localVideoPath = localVideoPath
        self.localThumbnailPath = localThumbnailPath
        self.isSelected = isSelected
    }
    
    var url: URL {
        if let localPath = localVideoPath {
            // For local videos, we should use the bundle URL, not documents directory
            return Bundle.main.bundleURL.appendingPathComponent(
                localPath.components(separatedBy: "/").last ?? ""
            )
        }
        // For remote videos, use the remote URL
        guard let remoteURL = remoteVideoURL else {
            fatalError("Video has neither local nor remote URL: \(displayTitle)")
        }
        return remoteURL
    }
    
    var remoteVideoURL: URL? {
        guard let remotePath = remoteVideoPath else { return nil }
        // R2 / CDN videos already store the full URL in remotePath
        if remotePath.hasPrefix("https://") { return URL(string: remotePath) }
        return URL(string: "https://\(AWSCredentials.bucketName).s3.\(AWSCredentials.region).amazonaws.com/\(remotePath)")
    }

    var remoteThumbnailURL: URL? {
        guard let thumbnailPath = remoteThumbnailPath else { return nil }
        // R2 / CDN thumbnails are publicly accessible — no signing needed
        if thumbnailPath.hasPrefix("https://") { return URL(string: thumbnailPath) }
        let s3Service = S3VideoService()
        let url = URL(string: "https://\(AWSCredentials.bucketName).s3.\(AWSCredentials.region).amazonaws.com/\(thumbnailPath)")!
        let request = s3Service.generateSignedRequest(for: url)
        return request.url
    }
    
    var title: String { displayTitle }
    
    // UI helper
    var displayTitleWithStatus: String {
        isLocal ? displayTitle : "\(displayTitle) (Remote)"
    }
    
    // Update the thumbnail URL logic
    var thumbnailURL: URL? {
        if FeatureFlags.generateThumbnails == false {
            if let localPath = localThumbnailPath {
                let filename = localPath.components(separatedBy: "/").last ?? localPath
                let localURL = Bundle.main.bundleURL.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    return localURL
                }
            }
            // Fall through to remote poster (R2 CDN videos)
            return remoteThumbnailURL
        }
        
        else {
            
            print("\n🔍 Checking thumbnail URL for: \(displayTitle)")
            print("Geozone: \(geozone)")
            print("Is local: \(isLocal)")
            
            if isLocal {
                // For local videos, check local thumbnail path
                if let localPath = localThumbnailPath {
                    // For local thumbnails, use bundle URL (same as videos)
                    // Extract just the filename from the path, similar to video URL logic
                    let filename = localPath.components(separatedBy: "/").last ?? localPath
                    let localURL = Bundle.main.bundleURL.appendingPathComponent(filename)
                    print("Checking local thumbnail at: \(localURL.path)")
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        print("✅ Found local thumbnail")
                        return localURL
                    } else {
                        print("❌ Local thumbnail file not found")
                    }
                }
                // Return nil to trigger thumbnail generation for local videos without thumbnails
                print("⚠️ No local thumbnail available")
                return nil
            } else {
                // For remote videos, use remote thumbnail URL directly
                if let remoteURL = remoteThumbnailURL {
                    print("✅ Using remote thumbnail URL: \(remoteURL.absoluteString)")
                    return remoteURL
                } else {
                    print("❌ No remote thumbnail URL available for video: \(displayTitle)")
                    print("   Remote path: \(remoteThumbnailPath ?? "nil")")
                    print("   Video ID: \(id)")
                    return nil
                }
            }
        }
    }
    
    // Create from VideoConfig metadata
    static func fromMetadata(_ metadata: VideoMetadata) -> Video {
        let fileManager = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        
        // Find video file in bundle
        let possibleExtensions = ["mp4", "mov"]
        var foundVideoPath: String? = nil
        
        for ext in possibleExtensions {
            let filename = "\(metadata.filename).\(ext)"
            let videoURL = bundleURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: videoURL.path) {
                foundVideoPath = filename
                print("📍 Found local video: \(videoURL.path)")
                break
            }
        }
        
        // Find thumbnail file in bundle (independent of video path)
        let thumbnailFilename = "\(metadata.filename).png"
        let thumbnailURL = bundleURL.appendingPathComponent(thumbnailFilename)
        let thumbnailPath = fileManager.fileExists(atPath: thumbnailURL.path) ? thumbnailFilename : nil
        
        if thumbnailPath != nil {
            print("📍 Found local thumbnail: \(thumbnailURL.path)")
        } else {
            print("⚠️ No local thumbnail found for: \(thumbnailFilename)")
        }
        
        // Create video with appropriate paths
        let video = Video(
            id: metadata.uuid,
            displayTitle: metadata.displayTitle,
            geozone: metadata.geozone,
            remoteVideoPath: nil,      // Always nil for local videos
            remoteThumbnailPath: nil,  // Always nil for local videos
            localVideoPath: foundVideoPath,  // Store just the filename
            localThumbnailPath: thumbnailPath,   // Store just the filename if found
            isSelected: true
        )
        
        return video
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayTitle
        case geozone
        case remoteVideoPath
        case remoteThumbnailPath
        case localVideoPath
        case localThumbnailPath
        case isSelected
    }
}

extension AVAsset {
    func loadValuesSync(forKeys keys: [String]) throws {
        var error: NSError?
        let timeout = DispatchTime.now() + 5.0 // 5 second timeout
        let semaphore = DispatchSemaphore(value: 0)
        
        loadValuesAsynchronously(forKeys: keys) {
            semaphore.signal()
        }
        
        if semaphore.wait(timeout: timeout) == .timedOut {
            throw NSError(domain: "AVAsset", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Timed out loading asset"])
        }
        
        for key in keys {
            var keysError: NSError?
            let status = statusOfValue(forKey: key, error: &keysError)
            if status == .failed {
                throw keysError ?? error ?? NSError(domain: "AVAsset", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load asset values"])
            }
        }
    }
} 
