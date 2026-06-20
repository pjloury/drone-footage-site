import os
import subprocess
import shutil
from pathlib import Path

def generate_thumbnail(video_path, timestamp="00:00:00"):
    """
    Generate a thumbnail from a video file using ffmpeg.
    
    Args:
        video_path (Path): Path to the video file
        timestamp (str): Timestamp to extract frame from (default: "00:00:00" for first frame)
    """
    try:
        # Create output filename (same name as video but .png extension)
        thumbnail_name = f"{video_path.stem}.png"
        thumbnail_path = video_path.parent / thumbnail_name
        
        # Check if thumbnail already exists
        if thumbnail_path.exists():
            print(f"⏭️  Thumbnail already exists for {video_path.name}, skipping...")
            return
        
        # Construct ffmpeg command
        cmd = [
            "ffmpeg",
            "-i", str(video_path),
            "-ss", timestamp,
            "-vframes", "1",
            "-vf", "scale=1920:1080",  # Scale to 1080p
            "-q:v", "2",  # High quality
            str(thumbnail_path)
        ]
        
        print(f"\nProcessing {video_path.name}...")
        subprocess.run(cmd, check=True, capture_output=True)
        print(f"✅ Generated thumbnail: {thumbnail_path}")
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Error processing {video_path.name}:")
        print(e.stderr.decode())
    except Exception as e:
        print(f"❌ Unexpected error for {video_path.name}:")
        print(str(e))

def find_video_files(directory):
    """
    Recursively find all video files in the given directory and its subdirectories.
    
    Args:
        directory (Path): Directory to search in
        
    Returns:
        list: List of Path objects for video files
    """
    video_extensions = ['.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv', '.webm']
    video_files = []
    
    try:
        for root, dirs, files in os.walk(directory):
            for file in files:
                file_path = Path(root) / file
                if file_path.suffix.lower() in video_extensions:
                    video_files.append(file_path)
    except Exception as e:
        print(f"❌ Error searching directory {directory}: {str(e)}")
    
    return video_files

def main():
    # Set up paths - look in the Videos folder
    video_dir = Path("Videos")
    
    if not video_dir.exists():
        print(f"❌ Videos directory not found: {video_dir}")
        return
    
    print(f"\n🔍 Searching for video files in: {video_dir}")
    
    # Find all video files recursively
    video_files = find_video_files(video_dir)
    
    if not video_files:
        print("No video files found in Videos directory or its subdirectories!")
        return
    
    print(f"\nFound {len(video_files)} video files")
    
    # Process each video
    for video_path in video_files:
        generate_thumbnail(video_path)
    
    print("\n✨ Thumbnail generation complete!")
    print(f"Processed {len(video_files)} video files")

if __name__ == "__main__":
    main()
