#!/usr/bin/env bash
# encode_and_upload.sh
# Encodes each active video into:
#   1. video-XX-mobile.mp4   — H.264 720p @ ~2 Mbps, faststart (mobile/fallback)
#   2. video-XX.mp4          — original re-muxed with faststart (desktop full-res)
#   3. video-XX-poster.jpg   — 720p still (~3s in) shown while the mp4 buffers
# Then uploads all three to R2 with long cache-control headers.
#
# Skips commented-out videos: 01 (Woodside Mansion), 25 (Home on Christmas), 28 (Flex)
#
# Usage:
#   bash encode_and_upload.sh                    # encode + upload anything missing in R2
#   bash encode_and_upload.sh --skip-desktop-upload
#                                                # don't re-upload desktop files
#   bash encode_and_upload.sh --force-mobile     # re-encode mobile even if already in R2
#                                                # (use after changing the mobile bitrate ladder)
#   bash encode_and_upload.sh --backfill-cache   # NO encoding — only re-stamps existing R2
#                                                # objects with Cache-Control + Content-Type.
#                                                # Run this immediately after deploying the
#                                                # custom-domain change to warm Cloudflare's
#                                                # edge cache and stop browsers re-downloading.

set -uo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SOURCE_DIR="/Users/Shared/Aerial Local"
OUTPUT_DIR="$HOME/Desktop/aerial_encoded"
ENDPOINT="https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com"
BUCKET="drone-footage"
PROFILE="r2"
LOG="$OUTPUT_DIR/encode_upload.log"

# Videos and posters never change once published — cache them forever.
CACHE_CONTROL="public, max-age=31536000, immutable"

SKIP_DESKTOP_UPLOAD=false
FORCE_MOBILE=false
BACKFILL_CACHE=false

for arg in "$@"; do
  case "$arg" in
    --skip-desktop-upload) SKIP_DESKTOP_UPLOAD=true ;;
    --force-mobile)        FORCE_MOBILE=true ;;
    --backfill-cache)      BACKFILL_CACHE=true ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
log_err() { echo "[$(date '+%H:%M:%S')] ❌ $*" | tee -a "$LOG" >&2; }

# ── Video map: number → local filename ───────────────────────────────────────
NUMS=(
  02 03 04 05 06 07 08 09 10
  11 12 13 14 15 16 17 18 19 20
  21 22 23 24 26 27 29 30
  31 32 33 34 35 36 37 38 39 40
  41 42 43 44 45 46 47 48 49 50
  51 52 53 54 55 56 57 58 59 60
  61 62
)

FILES=(
  "Good Morning Stanford.mov"
  "Snowy Tahoe Treetops.mov"
  "Carmel Waves at Dusk.mov"
  "Financial District.mov"
  "Heavenly Palo Alto.mov"
  "Telegraph Hill.mov"
  "Stanford Sunset.mov"
  "Above Soma.mov"
  "Los Altos Hills.mov"
  "Sterling VIneyard.mov"
  "Washington Square North Beach.mov"
  "New Office Site.mov"
  "Bay 2 Breakers.mov"
  "Wailea.mov"
  "Hvar, Croatia.mov"
  "Sather Tower.mov"
  "Villa Collina.mp4"
  "Waves.MP4"
  "Venice Canals.mov"
  "University of San Francisco.mov"
  "Old Valencia.mp4"
  "Arches.mov"
  "Mont Saint Michel.mov"
  "Salzburg.mov"
  "Park City Morning.mov"
  "Canyonlands.mov"
  "Vogelsang Lake, Yosemite.MP4"
  "Austria.mov"
  "Almaden Green.mp4"
  "Mont Saint Michel 2.mov"
  "SF LNY.mov"
  "Big Sur Hills.mov"
  "Fort Funston.mov"
  "Fort Funston with Golden Gate.mp4"
  "LA Burbs.mov"
  "Mont Saint Michel 3.mov"
  "Neuschwanstein Castle.mov"
  "Park City.mov"
  "Golden Gate Bridge.mov"
  "Balearic Islands.mov"
  "MSM 4.mov"
  "Drifting Away.mov"
  "Laguna de los Tres.mov"
  "Canyonlands 2.mov"
  "Ka'anapali Surf.mov"
  "Copacabana.mov"
  "Palma.mp4"
  "Fuschl am See.mov"
  "Moab.mov"
  "Carmel.mov"
  "Garrapata.mov"
  "Arches 2.mov"
  "Wailea South.mov"
  "Red Rocks.mov"
  "Salt Flats.mov"
  "Berkeley Campus.mov"
  "SF Embarcadero.mov"
  "Stanford Main Quad.mov"
  "Sather Tower.mp4"
)

TOTAL=${#NUMS[@]}
FAILED=()

# ─────────────────────────────────────────────────────────────────────────────
# BACKFILL MODE — metadata-only update on existing R2 objects.
# Use this RIGHT NOW (before any re-encoding) so existing files start
# returning Cache-Control: public, max-age=31536000, immutable.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$BACKFILL_CACHE" == "true" ]]; then
  log "Backfilling Cache-Control on existing R2 objects (no encoding)"
  log "Header: $CACHE_CONTROL"
  log ""

  backfill_one() {
    local KEY="$1"
    local CT="$2"
    # Skip if object doesn't exist
    if ! aws s3 ls "s3://$BUCKET/$KEY" \
        --profile "$PROFILE" --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
      return 0
    fi
    log "  ↻ $KEY"
    aws s3 cp "s3://$BUCKET/$KEY" "s3://$BUCKET/$KEY" \
      --profile "$PROFILE" \
      --endpoint-url "$ENDPOINT" \
      --metadata-directive REPLACE \
      --cache-control "$CACHE_CONTROL" \
      --content-type "$CT" \
      2>>"$LOG"
  }

  for NUM in "${NUMS[@]}"; do
    backfill_one "video-${NUM}.mp4"        "video/mp4"
    backfill_one "video-${NUM}-mobile.mp4" "video/mp4"
    backfill_one "video-${NUM}-poster.jpg" "image/jpeg"
  done

  log ""
  log "✅ Backfill complete. Cloudflare will repopulate edge cache on next request."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# NORMAL ENCODE + UPLOAD MODE
# ─────────────────────────────────────────────────────────────────────────────
log "Starting encode+upload for $TOTAL active videos"
log "Output dir: $OUTPUT_DIR"
log "Skip desktop upload: $SKIP_DESKTOP_UPLOAD"
log "Force re-encode mobile: $FORCE_MOBILE"
log "Cache-Control: $CACHE_CONTROL"
log ""

# ── Main loop ─────────────────────────────────────────────────────────────────
for i in "${!NUMS[@]}"; do
  NUM="${NUMS[$i]}"
  SRCFILE="${FILES[$i]}"
  SRC="$SOURCE_DIR/$SRCFILE"
  MOBILE_OUT="$OUTPUT_DIR/video-${NUM}-mobile.mp4"
  DESKTOP_OUT="$OUTPUT_DIR/video-${NUM}.mp4"
  POSTER_OUT="$OUTPUT_DIR/video-${NUM}-poster.jpg"
  CURRENT=$((i + 1))

  log "── ($CURRENT/$TOTAL) video-${NUM} ← \"$SRCFILE\""

  # Verify source exists
  if [[ ! -f "$SRC" ]]; then
    log_err "Source not found: $SRC — skipping"
    continue
  fi

  # ── Early exit: skip encode+upload if mobile already in R2 ───────────────
  # (unless --force-mobile was passed, e.g. after changing the encode ladder)
  MOBILE_KEY="video-${NUM}-mobile.mp4"
  if [[ "$FORCE_MOBILE" != "true" ]]; then
    ALREADY_IN_R2=$(aws s3 ls "s3://$BUCKET/$MOBILE_KEY" \
      --profile "$PROFILE" \
      --endpoint-url "$ENDPOINT" 2>/dev/null || true)
    if [[ -n "$ALREADY_IN_R2" ]]; then
      log "  already in R2, skipping (use --force-mobile to override)"
      log ""
      continue
    fi
  fi

  # ── Step 1: Encode mobile (H.264 1080p @ 5 Mbps + faststart) ─────────────
  # Restored to the original quality after the 720p@2M encode produced
  # visible graininess on phones. 5 Mbps with maxrate 7M / bufsize 10M
  # gives enough headroom that 60 fps motion clips don't overflow the
  # decode buffer the way they did at 2M. (See CLAUDE.md "60 fps source"
  # note for the original lurch diagnosis — the diagnosis was correct,
  # but the fix is "more bits" rather than "fewer frames".) Desktop
  # encode below stays `-c copy`, so full-res keeps original fps.
  if [[ -f "$MOBILE_OUT" ]]; then
    log "  mobile: already encoded locally, skipping ffmpeg"
  else
    log "  mobile: encoding H.264 1080p @ 5 Mbps..."
    if ffmpeg -i "$SRC" \
      -c:v libx264 -profile:v high -level 4.0 \
      -vf "scale=-2:1080" \
      -b:v 5M -maxrate 7M -bufsize 10M \
      -c:a aac -b:a 128k \
      -movflags +faststart \
      -y "$MOBILE_OUT" \
      2>>"$LOG"; then
      log "  mobile: done ($(du -sh "$MOBILE_OUT" | cut -f1))"
    else
      log_err "mobile encode FAILED for video-${NUM} (\"$SRCFILE\") — skipping"
      FAILED+=("video-${NUM}: $SRCFILE")
      continue
    fi
  fi

  # ── Step 2: Re-mux desktop with faststart (stream copy, no quality loss) ──
  if [[ -f "$DESKTOP_OUT" ]]; then
    log "  desktop: already muxed, skipping ffmpeg"
  else
    log "  desktop: re-muxing with faststart..."
    if ffmpeg -i "$SRC" \
      -c copy \
      -movflags +faststart \
      -y "$DESKTOP_OUT" \
      2>>"$LOG"; then
      log "  desktop: done ($(du -sh "$DESKTOP_OUT" | cut -f1))"
    else
      log_err "desktop mux FAILED for video-${NUM} (\"$SRCFILE\") — skipping"
      FAILED+=("video-${NUM}: $SRCFILE")
      continue
    fi
  fi

  # ── Step 3: Generate poster JPG (~3s into the clip, 720p tall) ──────────
  # Shown by the <video> element while the mp4 is still buffering — turns
  # the dreaded black screen into the "right" frame for the clip.
  if [[ -f "$POSTER_OUT" ]]; then
    log "  poster: already generated, skipping ffmpeg"
  else
    log "  poster: extracting frame at 00:00:03..."
    if ffmpeg -ss 00:00:03 -i "$SRC" \
      -vf "scale=-2:720" \
      -frames:v 1 -q:v 4 \
      -y "$POSTER_OUT" \
      2>>"$LOG"; then
      log "  poster: done ($(du -sh "$POSTER_OUT" | cut -f1))"
    else
      log_err "poster gen FAILED for video-${NUM} — continuing without"
    fi
  fi

  # ── Step 4: Upload mobile to R2 ───────────────────────────────────────────
  log "  upload mobile: uploading to R2..."
  aws s3 cp "$MOBILE_OUT" "s3://$BUCKET/$MOBILE_KEY" \
    --profile "$PROFILE" \
    --endpoint-url "$ENDPOINT" \
    --content-type "video/mp4" \
    --cache-control "$CACHE_CONTROL" \
    2>>"$LOG"
  log "  upload mobile: ✓ done"

  # ── Step 5: Upload desktop to R2 (replace existing) ───────────────────────
  DESKTOP_KEY="video-${NUM}.mp4"
  if [[ "$SKIP_DESKTOP_UPLOAD" == "true" ]]; then
    log "  upload desktop: skipped (--skip-desktop-upload)"
  else
    log "  upload desktop: uploading to R2 (faststart re-mux)..."
    aws s3 cp "$DESKTOP_OUT" "s3://$BUCKET/$DESKTOP_KEY" \
      --profile "$PROFILE" \
      --endpoint-url "$ENDPOINT" \
      --content-type "video/mp4" \
      --cache-control "$CACHE_CONTROL" \
      2>>"$LOG"
    log "  upload desktop: ✓ done"
  fi

  # ── Step 6: Upload poster to R2 ───────────────────────────────────────────
  if [[ -f "$POSTER_OUT" ]]; then
    POSTER_KEY="video-${NUM}-poster.jpg"
    log "  upload poster: uploading to R2..."
    aws s3 cp "$POSTER_OUT" "s3://$BUCKET/$POSTER_KEY" \
      --profile "$PROFILE" \
      --endpoint-url "$ENDPOINT" \
      --content-type "image/jpeg" \
      --cache-control "$CACHE_CONTROL" \
      2>>"$LOG"
    log "  upload poster: ✓ done"
  fi

  # ── Cleanup local encoded files to save disk space ────────────────────────
  rm -f "$MOBILE_OUT" "$DESKTOP_OUT" "$POSTER_OUT"
  log "  local files cleaned up"
  log ""
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "⚠️  Completed with ${#FAILED[@]} failure(s):"
  for f in "${FAILED[@]}"; do log "    FAILED: $f"; done
else
  log "✅ All $TOTAL videos processed successfully!"
fi
log ""
log "R2 bucket contents (video files):"
aws s3 ls "s3://$BUCKET/" \
  --profile "$PROFILE" \
  --endpoint-url "$ENDPOINT" \
  2>>"$LOG" | grep "video-" | tee -a "$LOG"
