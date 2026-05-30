# 🌍 Aerial Landscapes

> **A stunning collection of aerial landscape videos for Apple TV devices**

Transform your Apple TV into a mesmerizing digital window to the world with Aerial Landscapes! This app brings you breathtaking aerial footage from around the globe, perfect for creating an immersive ambient experience in your living room.

## ✨ What It Does

🎬 **Curated Video Collection**: Features stunning aerial footage from iconic locations worldwide, including:
- **United States**: Fort Funston, Red Rocks Nevada, Salt Flats, and more
- **International**: Balearic Islands Spain, Fuschl am See Austria, Hvar Croatia, Patagonia, and beyond

🎯 **Smart Playlist Management**: 
- Select your favorite videos to create custom playlists
- Videos play in shuffled order for endless variety
- Seamless looping between selected videos

🖼️ **Beautiful Thumbnails**: 
- Auto-generated thumbnails for local videos
- High-quality preview images for easy browsing
- Organized by geographic regions

☁️ **Cloud Integration**: 
- Optional S3 integration for remote video streaming
- Secure AWS authentication
- Metadata-driven video organization

## 🚀 How It Works

### Architecture Overview

The app is built with **SwiftUI** and uses a sophisticated video management system:

```
📱 App Structure
├── 🎬 VideoPlayerModel - Core video playback logic
├── 📂 VideoManager - Persistent video storage & selection
├── 🌐 S3VideoService - Cloud video integration
├── 🎨 ContentView - Main UI with tab navigation
└── 📋 MoreVideosView - Video selection interface
```

### Key Features

**🎮 Dual Interface**:
- **Now Playing**: Full-screen video experience with title overlay
- **More Videos**: Grid-based video browser with selection controls

**💾 Smart Storage**:
- Local video files stored in app bundle
- User selections persisted across app launches
- Automatic thumbnail generation for local content

**🔄 Playback Engine**:
- Built on `AVQueuePlayer` for seamless transitions
- Automatic playlist management
- Shuffled playback for variety

## 🎯 How to Use

### Getting Started

1. **Launch the App** 📱
   - Open Aerial Landscapes on your Apple TV or iOS device
   - You'll see the "Now Playing" screen with a welcome message

2. **Browse Videos** 🗂️
   - Tap the "More Videos" tab at the bottom
   - Videos are organized by region (United States & International)
   - Each video shows a beautiful thumbnail preview

3. **Create Your Playlist** ✅
   - Tap any video thumbnail to select/deselect it
   - Selected videos show a white checkmark
   - You can select multiple videos for a custom playlist

4. **Enjoy the Experience** 🎬
   - Return to "Now Playing" to watch your selected videos
   - Videos play in shuffled order and loop continuously
   - The current video title appears at the bottom

### Pro Tips

- **Minimum Selection**: You must have at least one video selected to play
- **Shuffled Playback**: Videos play in random order for variety
- **Seamless Looping**: When one video ends, the next begins automatically
- **Persistent Selection**: Your choices are saved between app launches

## 🛠️ Technical Details

### Video Formats
- **Supported**: `.mp4` and `.mov` files
- **Resolution**: Optimized for Apple TV display
- **Aspect Ratio**: 16:9 widescreen format

### Cloud Integration (Optional)
- **AWS S3**: Secure video storage and streaming
- **Metadata**: Videos tagged with display titles and geographic zones
- **Authentication**: AWS Signature Version 4 for secure access

### Performance Features
- **Lazy Loading**: Thumbnails load as needed
- **Memory Management**: Efficient video queue management
- **Background Processing**: Thumbnail generation happens off-main-thread

## 🎨 Customization

### Adding New Videos
1. Add video files to the `Videos/` directory in the app bundle
2. Update `VideoConfig.swift` with new video metadata
3. Include corresponding thumbnail images (`.png` format)

### Feature Flags
Control app behavior via `FeatureFlags.swift`:
- `enableTestVideos`: Include test video collection
- `enableRemoteVideos`: Enable S3 cloud integration
- `generateThumbnails`: Auto-generate thumbnails for local videos

## 🔧 Development

### Requirements
- **iOS 15.0+** / **tvOS 15.0+**
- **Xcode 14.0+**
- **Swift 5.7+**

### Dependencies
- **AVFoundation**: Video playback
- **SwiftUI**: User interface
- **CommonCrypto**: AWS authentication

### Building
1. Clone the repository
2. Open `AerialLandscapes.xcodeproj` in Xcode
3. Select your target device (Apple TV or iOS)
4. Build and run! 🚀

## 🌟 Inspiration

Inspired by Apple's own Aerial screensavers, this app brings the same sense of wonder and exploration to your Apple TV, with a curated collection of the world's most beautiful landscapes captured from above.

---

*Ready to transform your space into a window to the world? Download Aerial Landscapes and start your journey! 🌍✨*
