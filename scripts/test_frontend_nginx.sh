#!/usr/bin/env bash
# Smoke-test the prod frontend nginx config (frontend/nginx/default.conf)
# without a full Flutter build (#353 Option B / #356). Builds a minimal image
# on the same nginx base as frontend.Dockerfile.prod with dummy assets, then
# asserts:
#   - nginx config syntax (`nginx -t`)
#   - gzip Content-Encoding for .js / .wasm / .css / .woff2 (Accept-Encoding: gzip)
#   - no compression when the client does not request it
#   - Cache-Control: no-store (index.html) and no-cache (*.js)
#   - Vary: Accept-Encoding on compressed responses
#   - SPA fallback to index.html for unknown routes
#
# Run: scripts/test_frontend_nginx.sh   (needs Docker)
#
# This is the regression guard for the prod web-server compression config — a
# broken nginx.conf would silently 502 the next deploy, so the config lives in
# a committed file (not an inline `echo`) and is exercised here in CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONF="$REPO_ROOT/frontend/nginx/default.conf"

if [ ! -f "$CONF" ]; then
    echo "❌ frontend/nginx/default.conf not found at $CONF" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "❌ docker not found; this test requires Docker" >&2
    exit 1
fi

IMAGE_TAG="ymatch/frontend-nginx-test:$$"
CTR=""
WORKDIR="$(mktemp -d)"
cleanup() {
    if [ -n "$CTR" ]; then docker rm -f "$CTR" >/dev/null 2>&1 || true; fi
    docker rmi "$IMAGE_TAG" >/dev/null 2>&1 || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# --- Build a minimal image: prod nginx base + real config + dummy assets ---
# Asset content is >256 bytes (gzip_min_length) so gzip actually engages.
cp "$CONF" "$WORKDIR/default.conf"
cat > "$WORKDIR/Dockerfile" <<'EOF'
FROM ghcr.io/menonu/ymatch/nginx:alpine
COPY default.conf /etc/nginx/conf.d/default.conf
RUN mkdir -p /usr/share/nginx/html/assets/fonts \
    && yes "const hello = 'world'; " | head -c 1200 > /usr/share/nginx/html/main.dart.js \
    && yes "body { color: black; } " | head -c 1200 > /usr/share/nginx/html/styles.css \
    && yes "wasm-payload" | head -c 1200 > /usr/share/nginx/html/canvaskit.wasm \
    && yes "woff2-payload" | head -c 1200 > /usr/share/nginx/html/assets/fonts/NotoSansJP-Regular.woff2 \
    && printf '<!DOCTYPE html><html><head><title>ymatch</title></head><body><div id="app"></div></body></html>\n' > /usr/share/nginx/html/index.html \
    # Pre-compress .gz sidecars so gzip_static (the prod path) is exercised,
    # not just the dynamic fallback. Mirrors frontend.Dockerfile.prod.
    && find /usr/share/nginx/html -type f \
         \( -name '*.js' -o -name '*.wasm' -o -name '*.css' -o -name '*.woff2' \) \
       -exec gzip -kf {} \;
EOF

echo "▶ Building test image $IMAGE_TAG …"
docker build -q -t "$IMAGE_TAG" "$WORKDIR" >/dev/null

# Validate config syntax inside the image.
docker run --rm "$IMAGE_TAG" nginx -t >/dev/null

PORT="$((10000 + (RANDOM % 50000)))"
CTR="$(docker run -d --rm -p "$PORT:80" --name "ymatch-nginx-test-$$" "$IMAGE_TAG")"
trap cleanup EXIT

# Wait for nginx to answer.
for _ in $(seq 1 20); do
    if curl -s -o /dev/null "http://127.0.0.1:$PORT/index.html"; then break; fi
    sleep 0.25
done

BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0

assert_eq() { # label expected actual
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "✅ $label"
        PASS=$((PASS + 1))
    else
        echo "❌ $label — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() { # label haystack needle
    local label="$1" needle="$3"
    if printf '%s' "$2" | grep -qi "$3"; then
        echo "✅ $label"
        PASS=$((PASS + 1))
    else
        echo "❌ $label — expected response to contain [$needle]"
        FAIL=$((FAIL + 1))
    fi
}

hdr() { # url extra_curl_args...  →  full response headers (status line + headers), one per line
    local url="$1"; shift
    curl -s -o /dev/null -D - "$@" "$BASE$url" | tr -d '\r'
}

# --- gzip on compressible assets ---
for asset in /main.dart.js /canvaskit.wasm /styles.css /assets/fonts/NotoSansJP-Regular.woff2; do
    H="$(hdr "$asset" -H 'Accept-Encoding: gzip')"
    enc="$(printf '%s\n' "$H" | awk 'tolower($1)=="content-encoding:"{print $2}' | tr -d '\r')"
    vary="$(printf '%s\n' "$H" | awk 'tolower($1)=="vary:"{print $2}' | tr -d '\r')"
    assert_eq "$asset gzip Content-Encoding" "gzip" "$enc"
    assert_eq "$asset Vary: Accept-Encoding" "Accept-Encoding" "$vary"
done

# --- gzip_static serves the pre-built .gz sidecar, not dynamic gzip ---
# The on-the-wire gzipped body must be byte-identical to the sidecar file
# baked into the image (dynamic gzip at comp_level 5 would differ).
sidecar_bytes="$(docker exec "$CTR" sh -c 'wc -c < /usr/share/nginx/html/main.dart.js.gz' | tr -d ' \r\n')"
wire_bytes="$(curl -s -H 'Accept-Encoding: gzip' "$BASE/main.dart.js" | wc -c | tr -d ' \r\n')"
assert_eq "gzip_static serves pre-built .gz sidecar (wire bytes == sidecar bytes)" "$sidecar_bytes" "$wire_bytes"

# --- no compression when client doesn't request it ---
H="$(hdr /main.dart.js)"
enc="$(printf '%s\n' "$H" | awk 'tolower($1)=="content-encoding:"{print $2}' | tr -d '\r')"
if [ -z "$enc" ]; then
    echo "✅ no Content-Encoding without Accept-Encoding"; PASS=$((PASS + 1))
else
    echo "❌ expected no Content-Encoding without Accept-Encoding, got [$enc]"; FAIL=$((FAIL + 1))
fi

# --- Cache-Control headers ---
cc_index="$(hdr /index.html | awk 'tolower($1)=="cache-control:"{$1=""; print substr($0,2)}' | tr -d '\r')"
cc_js="$(hdr /main.dart.js | awk 'tolower($1)=="cache-control:"{$1=""; print substr($0,2)}' | tr -d '\r')"
assert_eq "index.html Cache-Control" "no-store" "$cc_index"
assert_eq "main.dart.js Cache-Control" "no-cache" "$cc_js"

# --- SPA fallback: unknown route serves index.html (200) ---
spa_status="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/some/deep/route")"
assert_eq "SPA fallback status" "200" "$spa_status"
spa_body="$(curl -s "$BASE/some/deep/route")"
assert_contains "SPA fallback body is index.html" "$spa_body" "<div id=\"app\"></div>"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
