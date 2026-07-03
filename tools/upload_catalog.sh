#!/usr/bin/env bash
# Upload catalog.json (the cloud source-of-truth for all video metadata:
# captions, category, map coordinates) to R2, served at
# https://videos.pjloury.com/catalog.json.
#
# Short cache (max-age=300) so newly-added videos/metadata appear in every
# client within a few minutes. The videos themselves stay immutable-cached.
#
# Run:  ./tools/upload_catalog.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENDPOINT="https://73fc4c58d8b8e9d05a8410bde37ff80d.r2.cloudflarestorage.com"
PROFILE="r2"

python3 -c "import json,sys; json.load(open('catalog.json')); print('catalog.json is valid JSON')"

aws s3 cp catalog.json "s3://drone-footage/catalog.json" \
    --profile "$PROFILE" --endpoint-url "$ENDPOINT" \
    --content-type "application/json" \
    --cache-control "public, max-age=300"

echo "✅  Uploaded to https://videos.pjloury.com/catalog.json"
