#!/usr/bin/env bash
# One-shot re-encode of the 8 Tier-1 heavy desktop clips (see CLAUDE.md) from
# their 4K sources to a streamable ~28 Mbps H.264, then upload to R2 so they can
# come back into the macOS playlist at full 4K resolution.
#
# H.264 (not HEVC) because these desktop URLs are also served to the website,
# where Chrome/Firefox can't decode HEVC. videos.pjloury.com is cf-cache-status
# DYNAMIC (not edge-cached), so overwriting the R2 object serves fresh bytes
# immediately — no cache-bust needed.
set -euo pipefail

SOURCE_DIR="/Users/Shared/Aerial Local"
OUT="$HOME/Desktop/aerial_reencode"
ENDPOINT="https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com"
BUCKET="drone-footage"
PROFILE="r2"
CACHE_CONTROL="public, max-age=31536000, immutable"
mkdir -p "$OUT"

NUMS=(18 19 22 30 32 37 50 62)

# bash 3.2 (macOS default) has no associative arrays — map with a case.
src_for() {
  case "$1" in
    18) echo "Villa Collina.mp4" ;;
    19) echo "Waves.MP4" ;;
    22) echo "Old Valencia.mp4" ;;
    30) echo "Vogelsang Lake, Yosemite.MP4" ;;
    32) echo "Almaden Green.mp4" ;;
    37) echo "Fort Funston with Golden Gate.mp4" ;;
    50) echo "Palma.mp4" ;;
    62) echo "Sather Tower.mp4" ;;
  esac
}

for n in "${NUMS[@]}"; do
  src="$SOURCE_DIR/$(src_for "$n")"
  out="$OUT/video-$n.mp4"
  [ -f "$src" ] || { echo "❌ missing source for $n: $src"; exit 1; }

  # Keyframe every ~2s based on source fps (helps the player recover/seek).
  fps_raw=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$src")
  fps=$(python3 -c "n,d='${fps_raw}'.split('/'); print(round(float(n)/float(d)))")
  gop=$(( fps * 2 ))

  echo "▸ [$n] encoding $(basename "$src") (fps≈$fps, GOP=$gop) → 28 Mbps H.264 4K"
  ffmpeg -y -i "$src" \
    -c:v h264_videotoolbox -profile:v high -b:v 28M -maxrate 34M -bufsize 68M \
    -g "$gop" -keyint_min "$gop" \
    -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    "$out" </dev/null

  # Report the result so we can confirm bitrate dropped into the safe zone.
  size=$(stat -f%z "$out"); dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$out")
  mbps=$(python3 -c "print(round($size*8/$dur/1e6,1))")
  echo "   → $((size/1024/1024))MB, ${mbps} Mbps avg"

  echo "▸ [$n] uploading to R2"
  aws s3 cp "$out" "s3://$BUCKET/video-$n.mp4" \
    --profile "$PROFILE" --endpoint-url "$ENDPOINT" \
    --content-type "video/mp4" --cache-control "$CACHE_CONTROL"
done

echo "✅ Re-encoded + uploaded: ${NUMS[*]}"
