import Foundation
import SwiftUI
import AVFoundation

class VideoManager: ObservableObject {
    static let shared = VideoManager()
    
    private let defaults = UserDefaults.standard
    private let videosKey = "savedVideos"
    
    @Published private(set) var videos: [Video] = [] {
        didSet {
            saveVideos()
            ensureLocalThumbnails()
        }
    }
    
    init() {
        // Restore saved videos from UserDefaults
        if let savedData = defaults.data(forKey: videosKey),
           let savedVideos = try? JSONDecoder().decode([Video].self, from: savedData) {
            videos = savedVideos
            print("\n📂 Restored \(videos.count) saved videos:")
            videos.forEach { video in
                print("- \(video.displayTitle)")
                print("  Remote Video URL: \(video.remoteVideoURL?.absoluteString ?? "nil")")
                print("  Remote Thumbnail URL: \(video.remoteThumbnailURL?.absoluteString ?? "nil")")
                print("  Local Video URL: \(video.localVideoPath ?? "nil")")
                print("  Local Thumbnail: \(video.localThumbnailPath ?? "nil")")
            }
        }
    }
    
    func updateSelection(for videoId: String, isSelected: Bool) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            // Force update the selection state
            videos[index].isSelected = isSelected
            saveVideos() // Persist selection state
            objectWillChange.send() // Notify observers of the change
            
            print("\n🔄 Updated selection state for video:")
            print("ID: \(videoId)")
            print("Title: \(videos[index].displayTitle)")
            print("New selection state: \(isSelected)")
        } else {
            print("⚠️ Attempted to update selection for non-existent video: \(videoId)")
        }
    }
    
    func updateLocalPath(for videoId: String, path: String) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].localVideoPath = path
            saveVideos()
            objectWillChange.send()
        }
    }
    
    func updateThumbnailPath(for videoId: String, path: String) {
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            videos[index].localThumbnailPath = path
            saveVideos()
            objectWillChange.send()
        }
    }
    
    private func generateThumbnail(for video: Video) async -> String? {
        print("\n🖼️ Generating thumbnail for: \(video.displayTitle)")
        print("Geozone: \(video.geozone)")
        print("Local video path: \(video.localVideoPath ?? "nil")")
        
        guard let localVideoPath = video.localVideoPath else {
            print("❌ No local video path found")
            return nil
        }
        
        let videoURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(localVideoPath)
        
        print("Video URL: \(videoURL.path)")
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            // Get the first frame
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            let cgImage = try await imageGenerator.image(at: time).image
            let uiImage = UIImage(cgImage: cgImage)
            
            // Create thumbnails directory if it doesn't exist
            let thumbnailsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Thumbnails")
            
            try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
            
            // Save thumbnail
            let thumbnailPath = "Thumbnails/\(video.id)_thumbnail.jpg"
            let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(video.id)_thumbnail.jpg")
            
            print("Saving thumbnail to: \(thumbnailURL.path)")
            
            if let data = uiImage.jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnailURL)
                print("✅ Thumbnail saved successfully")
                return thumbnailPath
            } else {
                print("❌ Failed to convert image to JPEG data")
                return nil
            }
        } catch {
            print("❌ Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    private func ensureLocalThumbnails() {
        let videosToProcess = videos.filter { video in
            video.isLocal && video.localThumbnailPath == nil
        }
        
        print("\n🔍 Checking thumbnails for \(videosToProcess.count) local videos")
        
        for video in videosToProcess {
            Task {
                if let thumbnailPath = await generateThumbnail(for: video) {
                    updateThumbnailPath(for: video.id, path: thumbnailPath)
                }
            }
        }
        
        print("\n✅ Thumbnail generation complete")
        print("   Total videos processed: \(videosToProcess.count)")
    }
    
    private func saveVideos() {
        if let encodedData = try? JSONEncoder().encode(videos) {
            defaults.set(encodedData, forKey: videosKey)
        }
    }
    
    func updateVideos(_ newVideos: [Video]) {
        // Preserve local paths and selection state when updating
        var updatedVideos = newVideos
        for (index, newVideo) in updatedVideos.enumerated() {
            if let existingVideo = videos.first(where: { $0.id == newVideo.id }) {
                updatedVideos[index].localVideoPath = existingVideo.localVideoPath
                updatedVideos[index].localThumbnailPath = existingVideo.localThumbnailPath
                updatedVideos[index].isSelected = existingVideo.isSelected
            }
        }
        videos = updatedVideos
        saveVideos()
    }
    
    func updateVideo(_ video: Video) {
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index] = video
            saveVideos()
        }
    }
} 