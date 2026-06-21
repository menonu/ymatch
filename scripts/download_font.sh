#!/bin/bash
# Download Noto Sans JP font for Flutter asset bundle (#291).
#
# The font file is gitignored (~5MB) to keep the repo small. This script
# fetches it from Google Fonts CDN so it's available for:
#   - flutter test (CI and local)
#   - flutter build web (CI and Docker)
#
# Run this before flutter test / flutter build web.
set -euo pipefail

FONT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/frontend/fonts"
FONT_FILE="$FONT_DIR/NotoSansJP-Regular.ttf"

if [ -f "$FONT_FILE" ]; then
  echo "Noto Sans JP font already present, skipping download."
  exit 0
fi

mkdir -p "$FONT_DIR"
echo "Downloading Noto Sans JP Regular from Google Fonts CDN..."
curl -sL -o "$FONT_FILE" \
  "https://fonts.gstatic.com/s/notosansjp/v56/-F6jfjtqLzI2JPCgQBnw7HFyzSD-AsregP8VFBEj75s.ttf"

if [ ! -s "$FONT_FILE" ]; then
  echo "ERROR: Failed to download Noto Sans JP font." >&2
  exit 1
fi

echo "Downloaded: $(wc -c < "$FONT_FILE") bytes -> $FONT_FILE"
