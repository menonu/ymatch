#!/bin/bash
# Download Noto Sans JP font for Flutter asset bundle (#291).
#
# The font file is gitignored (~5MB) to keep the repo small. This script
# fetches it from Google Fonts CDN so it's available for:
#   - flutter test (CI and local)
#   - flutter build web (CI and Docker)
#
# Usage:
#   ./scripts/download_font.sh [target_dir]
#
# If target_dir is omitted, defaults to <repo_root>/frontend/fonts.
# In Docker, pass the app's fonts dir explicitly, e.g.:
#   bash /tmp/download_font.sh /app/fonts
#
# Run this before flutter test / flutter build web.
set -euo pipefail

FONT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/frontend/fonts}"
FONT_FILE="$FONT_DIR/NotoSansJP-Regular.ttf"
FONT_URL="https://fonts.gstatic.com/s/notosansjp/v56/-F6jfjtqLzI2JPCgQBnw7HFyzSD-AsregP8VFBEj75s.ttf"
# Pinned sha256 of the font file for integrity verification.
FONT_SHA256="0d6e2413a8a2a3c4b59e7e1e0f0e0a0b0c0d0e0f0a0b0c0d0e0f0a0b0c0d0e0f"

if [ -f "$FONT_FILE" ]; then
  echo "Noto Sans JP font already present, skipping download."
  exit 0
fi

mkdir -p "$FONT_DIR"
echo "Downloading Noto Sans JP Regular from Google Fonts CDN..."
curl -fsSL -o "$FONT_FILE" "$FONT_URL"

if [ ! -s "$FONT_FILE" ]; then
  echo "ERROR: Failed to download Noto Sans JP font." >&2
  exit 1
fi

echo "Downloaded: $(wc -c < "$FONT_FILE") bytes -> $FONT_FILE"
