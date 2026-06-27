#!/usr/bin/env bash
# Upload the locally-staged re-encoded heavy clips (~/Desktop/aerial_reencode/
# video-NN.mp4, produced by reencode_heavy.sh) to R2.
#
# Run this AFTER refreshing the R2 token in ~/.aws/credentials [r2] — the
# encodes are already done, so this is just the upload step.
#
# Quick credential check first:
#   aws s3 ls s3://drone-footage/ --profile r2 \
#     --endpoint-url https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com
set -euo pipefail

OUT="$HOME/Desktop/aerial_reencode"
ENDPOINT="https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com"
BUCKET="drone-footage"
PROFILE="r2"
CACHE_CONTROL="public, max-age=31536000, immutable"
NUMS=(18 19 22 30 32 37 50 62)

for n in "${NUMS[@]}"; do
  f="$OUT/video-$n.mp4"
  [ -f "$f" ] || { echo "❌ missing staged encode: $f (run reencode_heavy.sh first)"; exit 1; }
  echo "▸ uploading video-$n.mp4 ($(( $(stat -f%z "$f") / 1024 / 1024 ))MB)"
  # put-object = single request (no multipart); all clips are well under R2's
  # 5 GB single-PUT limit.
  aws s3api put-object --bucket "$BUCKET" --key "video-$n.mp4" --body "$f" \
    --content-type "video/mp4" --cache-control "$CACHE_CONTROL" \
    --profile "$PROFILE" --endpoint-url "$ENDPOINT" >/dev/null
done

echo "✅ Uploaded: ${NUMS[*]}"
echo "   Now flip VideoPlaylist.excludedHeavyIDs to [] and rebuild the Mac app."
