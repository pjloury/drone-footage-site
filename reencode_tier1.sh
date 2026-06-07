#!/usr/bin/env bash
# Re-encode the 8 Tier-1 high-bitrate desktop clips to H.264 15 Mbps.
# Uploads each to R2, overwriting the existing file.
# Run from repo root.

set -euo pipefail

SOURCE_DIR="/Users/Shared/Aerial Local"
OUTPUT_DIR="$HOME/Desktop/aerial_encoded"
ENDPOINT="https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com"
BUCKET="drone-footage"
PROFILE="r2"
CACHE_CONTROL="public, max-age=31536000, immutable"
LOG="$OUTPUT_DIR/reencode_tier1.log"

mkdir -p "$OUTPUT_DIR"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

srcfile_for() {
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

FAILED=()

for NUM in 18 19 22 30 32 37 50 62; do
  SRCFILE=$(srcfile_for "$NUM")
  SRC="$SOURCE_DIR/$SRCFILE"
  OUT="$OUTPUT_DIR/video-$(printf '%02d' $NUM).mp4"
  KEY="video-$(printf '%02d' $NUM).mp4"

  log "── video-$(printf '%02d' $NUM) ← \"$SRCFILE\""

  if [[ ! -f "$SRC" ]]; then
    log "  ERROR: source not found: $SRC"
    FAILED+=("$KEY")
    continue
  fi

  log "  encoding H.264 15 Mbps (h264_videotoolbox)..."
  if ffmpeg -i "$SRC" \
    -map 0:v:0 -map 0:a? \
    -c:v h264_videotoolbox \
    -b:v 15M \
    -profile:v high \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    -y "$OUT" \
    2>>"$LOG"; then
    log "  encoded: $(du -sh "$OUT" | cut -f1)"
  else
    log "  h264_videotoolbox failed, falling back to libx264..."
    if ffmpeg -i "$SRC" \
      -map 0:v:0 -map 0:a? \
      -c:v libx264 -preset veryfast \
      -b:v 15M -maxrate 20M -bufsize 30M \
      -c:a aac -b:a 128k \
      -movflags +faststart \
      -y "$OUT" \
      2>>"$LOG"; then
      log "  encoded: $(du -sh "$OUT" | cut -f1)"
    else
      log "  ERROR: encode failed for $KEY"
      FAILED+=("$KEY")
      continue
    fi
  fi

  log "  uploading to R2..."
  if aws s3 cp "$OUT" "s3://$BUCKET/$KEY" \
    --profile "$PROFILE" \
    --endpoint-url "$ENDPOINT" \
    --content-type "video/mp4" \
    --cache-control "$CACHE_CONTROL" \
    2>>"$LOG"; then
    log "  uploaded OK"
  else
    log "  ERROR: upload failed for $KEY"
    FAILED+=("$KEY")
    continue
  fi

  log ""
done

log "══════════════════════════════════════════"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  log "All 8 clips re-encoded and uploaded successfully."
  log "Next: bump DESKTOP_VERSION in index.html and push."
else
  log "FAILED: ${FAILED[*]}"
fi
