import Foundation
import AVKit
import AVFoundation
import SwiftUI

class VideoPlayerModel: NSObject, ObservableObject {
    @Published var currentVideoTitle: String = ""
    let player: AVQueuePlayer
    @Published private(set) var videos: [Video] = []
    
    // Track currently playing index
    private var currentPlaylistIndex: Int = 0
    
    // Add a property to track the current playlist order
    private var currentPlaylist: [Video] = []
    
    // Get selected videos in a computed property
    var selectedVideos: [Video] {
        return videos.filter { $0.isLocal && $0.isSelected }
    }
    
    // Add S3 service
    let s3VideoService = S3VideoService()
    
    @Published private(set) var isInitialLoad = true
    
    @Published private(set) var remoteVideos: [Video] = []
    
    @Published var downloadProgress: [String: Double] = [:]
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var videosDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("Videos")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    
    private var thumbnailsDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    
    private var videoConfig: VideoConfig {
        return VideoConfig.shared
    }
    
    private let videoManager = VideoManager.shared
    
    override init() {
        self.player = AVQueuePlayer()
        super.init()
        
        // Set up observers
        setupPlayerObserver()
        addPlayerObserver()
        
        // Initialize VideoManager with default from Config
        let defaultVideos = videoConfig.videos.map(Video.fromMetadata)
        videoManager.updateVideos(defaultVideos)
            
//            // First launch - select all local videos by default
//            defaultVideos.forEach { video in
//                if video.isLocal {
//                    videoManager.updateSelection(for: video.id, isSelected: true)
//                }
//            }
//        }
        
        // Load initial state
        loadVideos()
        
        // Start fetching remote videos after initial setup
        if FeatureFlags.enableRemoteVideos {
            fetchRemoteVideos()
        }
    }
    
    private func loadVideos() {
        videos = videoManager.videos
        
        print("\n📱 Loading \(videos.count) videos from persistent storage:")
        
        // 1. Generate thumbnails for local videos (fast, do immediately)
        if FeatureFlags.generateThumbnails {
            generateThumbnailsForLocalVideos(videos)
        }
        
        // 2. Update UI with what we have
        DispatchQueue.main.async { [weak self] in
            self?.updateSelectedVideos(self?.videos ?? [])
        }
        
        if FeatureFlags.enableRemoteVideos {
            // 3. Start async thumbnail downloads for remote videos
            Task {
                await downloadRemoteThumbnails()
                
                // 4. Final validation
                DispatchQueue.main.async { [weak self] in
                    self?.validateThumbnails()
                    self?.objectWillChange.send()  // Refresh UI
                }
            }
        }
    }
    
    private func fetchRemoteVideos() {
        s3VideoService.fetchAvailableVideos { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let newVideos):
                    // Update or add new videos to VideoManager
                    var existingVideos = self?.videoManager.videos ?? []
                    
                    print("\n☁️ Fetched \(newVideos.count) remote videos:")
                    for remoteVideo in newVideos {
                        if let existingIndex = existingVideos.firstIndex(where: { $0.id == remoteVideo.id }) {
                            // Preserve local paths and selection state
                            var updatedVideo = remoteVideo
                            updatedVideo.localVideoPath = existingVideos[existingIndex].localVideoPath
                            updatedVideo.localThumbnailPath = existingVideos[existingIndex].localThumbnailPath
                            updatedVideo.isSelected = existingVideos[existingIndex].isSelected
                            
                            // Update existing video
                            existingVideos[existingIndex] = updatedVideo
                            print("📝 Updated existing video: \(updatedVideo.displayTitle)")
                            print("  Preserved local thumbnail: \(updatedVideo.localThumbnailPath ?? "nil")")
                        } else {
                            // Add new video
                            existingVideos.append(remoteVideo)
                            print("➕ Added new video: \(remoteVideo.displayTitle)")
                        }
                    }
                    
                    self?.videoManager.updateVideos(existingVideos)
                    self?.videos = existingVideos  // Update local reference
                    self?.remoteVideos = newVideos // Update remote videos list
                    print("\n✅ Updated video cache with \(newVideos.count) remote videos")
                    
                case .failure(let error):
                    print("❌ Error fetching remote videos: \(error)")
                }
                self?.isInitialLoad = false
            }
        }
    }
    
    // Setup player observer for end of video
    private func setupPlayerObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let finishedItem = notification.object as? AVPlayerItem else { return }
            
            guard !currentPlaylist.isEmpty else { return }
            
            // Remove the finished item
            self.player.remove(finishedItem)
            
            // Increment index and wrap around if needed
            currentPlaylistIndex = (currentPlaylistIndex + 1) % currentPlaylist.count
            
            // Get the next video from our stored playlist order
            let nextVideo = currentPlaylist[currentPlaylistIndex]
            
            // Create new player item and add to queue
            let playerItem = AVPlayerItem(url: nextVideo.url)
            self.player.insert(playerItem, after: self.player.items().last)
            addPlayerItemObserver(playerItem, title: nextVideo.displayTitle)
            
            // Ensure playback continues
            self.player.play()
            
            // Update title after ensuring the player has started playing the next item
            DispatchQueue.main.async {
                if let currentItem = self.player.currentItem,
                   let currentVideo = self.getVideo(from: currentItem) {
                    self.currentVideoTitle = currentVideo.displayTitle
                }
            }
        }
        
        // Add observer for when the current item changes
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let currentItem = self.player.currentItem,
                  let currentVideo = self.getVideo(from: currentItem) else { return }
            
            self.currentVideoTitle = currentVideo.displayTitle
        }
    }
    
    func updateSelectedVideos(_ videos: [Video]) {
        let selectedVideos = self.selectedVideos
        guard !selectedVideos.isEmpty else {
            player.removeAllItems()
            currentVideoTitle = ""
            currentPlaylistIndex = 0
            currentPlaylist = []
            return
        }
        
        // Clear existing queue and reset index
        player.removeAllItems()
        currentPlaylistIndex = 0
        
        // Shuffle the selected videos for variety
        let shuffledVideos = selectedVideos.shuffled()
        // Store the shuffled order
        currentPlaylist = shuffledVideos
        
        // Add all selected videos to queue
        for video in shuffledVideos {
            let playerItem = AVPlayerItem(url: video.url)
            player.insert(playerItem, after: player.items().last)
            addPlayerItemObserver(playerItem, title: video.displayTitle)
        }
        
        // Set initial title and start playback
        if let firstVideo = shuffledVideos.first {
            // Update title immediately before starting playback
            currentVideoTitle = firstVideo.displayTitle
            
            // Ensure we're at the start of the video
            player.seek(to: .zero)
            
            // Force playback to start
            DispatchQueue.main.async {
                self.player.play()
            }
        }
    }
    
    private func addPlayerItemObserver(_ item: AVPlayerItem, title: String) {
        // Observe status changes
        item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: nil)
        
        // Observe if playback is likely to keep up
        item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp), options: [.old, .new], context: nil)
        
        // Add error observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
    }
    
    private func addPlayerObserver() {
        // Observe player's timeControlStatus
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options: [.old, .new], context: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let item = object as? AVPlayerItem {
            switch keyPath {
            case #keyPath(AVPlayerItem.status):
                if let error = item.error {
                    print("Error: \(error.localizedDescription)")
                }
            default:
                break
            }
        }
    }
    
    @objc private func playerItemFailedToPlay(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem,
           let error = item.error {
            print("❌ Player item failed to play: \(error.localizedDescription)")
            
            if let urlAsset = item.asset as? AVURLAsset {
                print("Failed URL: \(urlAsset.url)")
            }
        }
    }
    
    deinit {
        // Remove timeObserver cleanup since we're not using it anymore
        NotificationCenter.default.removeObserver(self)
        
        player.items().forEach { item in
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp))
        }
        
        player.removeObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus))
    }
    
    var allVideos: [Video] {
        // Get the list of downloaded video titles
        let downloadedTitles = Set(videos.map { $0.displayTitle })
        
        // Start with all local videos
        var orderedVideos = videos
        
        // Add only remote videos that aren't already downloaded
        let nonDownloadedRemoteVideos = remoteVideos.filter { !downloadedTitles.contains($0.displayTitle) }
        orderedVideos.append(contentsOf: nonDownloadedRemoteVideos)
        
        return orderedVideos
    }
    
    func downloadAndAddVideo(_ video: Video, completion: @escaping (Bool) -> Void) {
        print("\n📥 Starting download for: \(video.displayTitle)")
        
        guard let remotePath = video.remoteVideoPath else {
            print("❌ No remote video path available")
            completion(false)
            return
        }
        
        let request = s3VideoService.generateSignedRequest(for: video)
        
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Download failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.downloadProgress.removeValue(forKey: video.id)
                    completion(false)
                }
                return
            }
            
            guard let tempURL = tempURL,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                print("❌ Invalid response or missing file")
                DispatchQueue.main.async {
                    self.downloadProgress.removeValue(forKey: video.id)
                    completion(false)
                }
                return
            }
            
            do {
                let finalURL = self.videosDirectory.appendingPathComponent(remotePath)
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
                
                // Update the local path after successful move
                let relativePath = "Videos/\(remotePath)"
                
                DispatchQueue.main.async {
                    self.videoManager.updateLocalPath(for: video.id, path: relativePath)
                    self.downloadProgress.removeValue(forKey: video.id)
                    completion(true)
                }
                
            } catch {
                print("❌ Failed to save video: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.downloadProgress.removeValue(forKey: video.id)
                    completion(false)
                }
            }
        }
        
        // Show download progress
        task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] (progress: Progress, _) in
            DispatchQueue.main.async {
                self?.downloadProgress[video.id] = progress.fractionCompleted
            }
        }
        
        task.resume()
    }
    
    func ensureThumbnail(for video: Video) -> URL? {
        guard let localPath = video.localThumbnailPath else {
            print("⚠️ No thumbnail path for video: \(video.displayTitle)")
            return nil
        }
        
        let thumbnailURL = documentsDirectory.appendingPathComponent(localPath)
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            return thumbnailURL
        }
        
        print("⚠️ Thumbnail file missing for: \(video.displayTitle)")
        return nil
    }
    
    private func generateThumbnailsForLocalVideos(_ videos: [Video]) {
        print("\n🎬 Starting batch thumbnail generation for local videos...")
        
        let videosNeedingThumbnails = videos.filter { video in
            guard video.isLocal else { return false }
            
            // Check if thumbnail already exists in filesystem
            if let localPath = video.localThumbnailPath {
                let thumbnailURL = documentsDirectory.appendingPathComponent(localPath)
                if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                    print("✅ Thumbnail already exists for \(video.displayTitle): \(thumbnailURL.path)")
                    return false
                }
            }
            
            // Check if thumbnail exists but path isn't saved
            let expectedThumbnailPath = "Thumbnails/\(video.id).jpg"
            let expectedURL = documentsDirectory.appendingPathComponent(expectedThumbnailPath)
            if FileManager.default.fileExists(atPath: expectedURL.path) {
                print("📝 Found existing thumbnail for \(video.displayTitle), updating path")
                // Update the video object directly
                if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                    self.videos[index].localThumbnailPath = expectedThumbnailPath
                }
                return false
            }
            
            return true
        }
        
        print("Found \(videosNeedingThumbnails.count) videos needing thumbnails")
        
        for video in videosNeedingThumbnails {
            print("\n📸 Processing: \(video.displayTitle)")
            if let thumbnailURL = generateThumbnail(from: video.url, videoId: video.id) {
                let relativePath = "Thumbnails/\(video.id).jpg"
                
                // Update the video object directly
                if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                    self.videos[index].localThumbnailPath = relativePath
                }
                
                // Also update VideoManager for persistence
                videoManager.updateThumbnailPath(for: video.id, path: relativePath)
                
                print("✅ Generated thumbnail for \(video.displayTitle)")
            } else {
                print("❌ Failed to generate thumbnail for \(video.displayTitle)")
            }
        }
        
        print("\n✅ Batch thumbnail generation complete")
        print("Successfully processed \(videosNeedingThumbnails.count) videos")
        
        // Trigger UI update to show the newly generated thumbnails
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    private func generateThumbnail(from videoURL: URL, videoId: String) -> URL? {
        print("\n📸 Generating thumbnail for video at: \(videoURL.path)")
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Create thumbnails directory if needed
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(videoId).jpg")
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                try jpegData.write(to: thumbnailURL)
                print("✅ Saved thumbnail to: \(thumbnailURL.path)")
                return thumbnailURL
            }
        } catch {
            print("❌ Failed to generate thumbnail: \(error)")
        }
        
        return nil
    }
    
    private func downloadThumbnail(for video: Video, completion: @escaping (Bool) -> Void) {
        guard let remoteThumbnailURL = video.remoteThumbnailURL else {
            print("❌ No remote thumbnail URL available for video: \(video.displayTitle)")
            completion(false)
            return
        }
        
        print("\n📥 Starting thumbnail download:")
        print("Video: \(video.displayTitle)")
        print("Remote URL: \(remoteThumbnailURL)")
        
        // Create signed request for the thumbnail
        let request = s3VideoService.generateSignedRequest(for: remoteThumbnailURL)
        
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Thumbnail download failed: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Thumbnail response status: \(httpResponse.statusCode)")
            }
            
            guard let tempURL = tempURL,
                  let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                print("❌ Invalid thumbnail response or missing file")
                print("Response: \(String(describing: response))")
                completion(false)
                return
            }
            
            do {
                // Ensure thumbnails directory exists
                try FileManager.default.createDirectory(at: self.thumbnailsDirectory, 
                                                     withIntermediateDirectories: true)
                
                // Create final thumbnail URL
                let localThumbnailPath = "Thumbnails/\(video.id).jpg"
                let finalURL = self.documentsDirectory.appendingPathComponent(localThumbnailPath)
                
                print("\n💾 Saving thumbnail:")
                print("From: \(tempURL.path)")
                print("To: \(finalURL.path)")
                
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                    print("🗑️ Removed existing thumbnail")
                }
                
                // Move downloaded file to final location
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
            
            DispatchQueue.main.async {
                    // Update video model with local thumbnail path
                    self.videoManager.updateThumbnailPath(for: video.id, path: localThumbnailPath)
                    print("✅ Successfully saved thumbnail and updated path")
                    
                    // Force UI refresh for this video
                    if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                        self.objectWillChange.send()
                        self.videos[index].localThumbnailPath = localThumbnailPath
                    }
                    
                completion(true)
                }
            } catch {
                print("❌ Failed to save thumbnail: \(error)")
                print("Error details: \(error.localizedDescription)")
                completion(false)
            }
        }
        
        task.resume()
    }
    
    // Add this public method to VideoPlayerModel
    func toggleVideoSelection(for videoId: String) {
        print("\n🔄 Toggling video selection:")
        
        // Get current selection state
        let currentState = videoManager.videos.first(where: { $0.id == videoId })?.isSelected ?? false
        let newState = !currentState
        
        print("Video ID: \(videoId)")
        print("Current state: \(currentState)")
        print("New state: \(newState)")
        
        // Prevent deselecting the last local video
        if currentState {
            let selectedLocalVideos = videos.filter { $0.isLocal && $0.isSelected }
            if selectedLocalVideos.count <= 1 {
                print("⚠️ Cannot deselect last local video")
                return
            }
        }
        
        // Update selection state in VideoManager
        videoManager.updateSelection(for: videoId, isSelected: newState)
        
        // Update local videos array
        videos = videoManager.videos
        
        // Update player playlist
        updateSelectedVideos(videos)
        
        print("✅ Selection state updated successfully")
    }
    
    // Add a method to get the current video from a player item
    private func getVideo(from playerItem: AVPlayerItem) -> Video? {
        guard let asset = playerItem.asset as? AVURLAsset else { return nil }
        return currentPlaylist.first { $0.url == asset.url }
    }
    
    private func validateThumbnails() {
        print("\n🔍 Validating thumbnails for all videos...")
        
        for video in videos {
            if video.isLocal {
                // Local videos should have local thumbnails
                if video.localThumbnailPath == nil {
                    print("⚠️ Local video missing thumbnail path: \(video.displayTitle)")
                    continue
                }
                
                let thumbnailURL = documentsDirectory.appendingPathComponent(video.localThumbnailPath!)
                if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
                    print("❌ Thumbnail file missing for local video: \(video.displayTitle)")
                    print("   Expected path: \(thumbnailURL.path)")
                }
            }
        }
    }
    
    private func downloadRemoteThumbnails() async {
        print("\n🌐 Starting batch download of remote thumbnails...")
        
        // Find ALL videos with remote thumbnails that need downloading
        let videosNeedingThumbnails = videos.filter { video in
            if let localPath = video.localThumbnailPath {
                let localURL = documentsDirectory.appendingPathComponent(localPath)
                return !FileManager.default.fileExists(atPath: localURL.path)
            }
            return video.remoteThumbnailURL != nil
        }
        
        print("Found \(videosNeedingThumbnails.count) videos needing remote thumbnails")
        
        await withTaskGroup(of: Void.self) { group in
            for video in videosNeedingThumbnails {
                group.addTask {
                    await self.downloadThumbnailAsync(for: video)
                }
            }
        }
        
        print("\n✅ Completed batch thumbnail download")
        DispatchQueue.main.async {
            self.objectWillChange.send()  // Refresh UI after all downloads complete
        }
    }
    
    private func downloadThumbnailAsync(for video: Video) async {
        return await withCheckedContinuation { continuation in
            downloadThumbnail(for: video) { success in
                if success {
                    print("✅ Downloaded thumbnail for: \(video.displayTitle)")
                } else {
                    print("❌ Failed to download thumbnail for: \(video.displayTitle)")
                }
                continuation.resume()
            }
        }
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 
