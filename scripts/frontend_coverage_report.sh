#!/usr/bin/env bash
# Filter Flutter LCOV and report line coverage (#453).
#
# Excludes generated / non-actionable sources so the headline % matches
# hand-written app code (same idea as cargo-llvm-cov --ignore-filename-regex
# 'generated/' on the backend):
#   - lib/generated/**          (protobuf bindings)
#   - lib/l10n/app_localizations*.dart  (flutter gen-l10n output)
#
# Usage (from repo root or anywhere):
#   scripts/frontend_coverage_report.sh <lcov.info> [--threshold N] [--output PATH]
#
# Defaults:
#   --output  <dir-of-input>/lcov.filtered.info
#   no threshold gate unless --threshold is set
#
# Prints a one-line summary and exits 1 if coverage is below the threshold
# or if the filtered set has zero instrumented lines.
#
# Pure bash + awk — no lcov package required (CI-friendly).

set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage: scripts/frontend_coverage_report.sh <lcov.info> [--threshold N] [--output PATH]

  --threshold N   Fail if filtered line coverage is below N percent.
  --output PATH   Write filtered LCOV here (default: <input-dir>/lcov.filtered.info).
  -h, --help      Show this help.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -lt 1 ]; then
  usage
  [ $# -lt 1 ] && exit 2
  exit 0
fi

INPUT=""
THRESHOLD=""
OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold)
      THRESHOLD="${2:?--threshold requires a number}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:?--output requires a path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [ -n "$INPUT" ]; then
        echo "Unexpected argument: $1" >&2
        usage
        exit 2
      fi
      INPUT="$1"
      shift
      ;;
  esac
done

if [ -z "$INPUT" ]; then
  usage
  exit 2
fi

if [ ! -s "$INPUT" ]; then
  echo "::error::LCOV file missing or empty: $INPUT" >&2
  exit 1
fi

if [ -z "$OUTPUT" ]; then
  OUTPUT="$(dirname "$INPUT")/lcov.filtered.info"
fi

mkdir -p "$(dirname "$OUTPUT")"
TOTALS_FILE="$(mktemp)"
trap 'rm -f "$TOTALS_FILE"' EXIT

# Rewrite LCOV: drop SF records whose path matches excluded prefixes, and
# recompute LF/LH totals from remaining DA: lines so the file stays valid.
# Path match is substring-based so both `lib/generated/...` and absolute
# paths ending in `/lib/generated/...` are excluded.
awk -v totals_file="$TOTALS_FILE" '
  function is_excluded(path,   n) {
    n = path
    gsub(/\\/, "/", n)
    if (n ~ /(^|\/)lib\/generated\//) return 1
    if (n ~ /(^|\/)lib\/l10n\/app_localizations(_[a-z]+)?\.dart$/) return 1
    return 0
  }

  function flush_record() {
    if (!in_record) return
    if (!skip) {
      print "SF:" sf
      for (i = 1; i <= n_da; i++) print da[i]
      if (has_fn) {
        for (i = 1; i <= n_fn; i++) print fn[i]
        if (fnf != "") print "FNF:" fnf
        if (fnh != "") print "FNH:" fnh
      }
      # Recompute from DA lines (LH/LF from Flutter can be stale after filter).
      print "LF:" n_da
      hit = 0
      for (i = 1; i <= n_da; i++) {
        split(da[i], parts, ",")
        if (parts[2] + 0 > 0) hit++
      }
      print "LH:" hit
      print "end_of_record"
      total_lf += n_da
      total_lh += hit
    }
    in_record = 0
    skip = 0
    n_da = 0
    n_fn = 0
    has_fn = 0
    fnf = ""
    fnh = ""
    sf = ""
    delete da
    delete fn
  }

  BEGIN {
    total_lf = 0
    total_lh = 0
    in_record = 0
  }

  /^SF:/ {
    flush_record()
    in_record = 1
    sf = substr($0, 4)
    skip = is_excluded(sf)
    next
  }

  /^end_of_record/ {
    flush_record()
    next
  }

  in_record && !skip {
    if ($0 ~ /^DA:/) {
      n_da++
      da[n_da] = $0
      next
    }
    if ($0 ~ /^FN:/) {
      has_fn = 1
      n_fn++
      fn[n_fn] = $0
      next
    }
    if ($0 ~ /^FNF:/) { has_fn = 1; fnf = substr($0, 5); next }
    if ($0 ~ /^FNH:/) { has_fn = 1; fnh = substr($0, 5); next }
    # Drop other per-record keys we do not re-emit (BRDA etc. unused by Dart).
    next
  }

  # Outside a record (or skipped): ignore.
  { next }

  END {
    flush_record()
    # Totals for the shell wrapper (stdout is the LCOV body only).
    printf "%d %d\n", total_lh, total_lf > totals_file
  }
' "$INPUT" >"$OUTPUT"

read -r LH LF <"$TOTALS_FILE"

if [ "${LF:-0}" -le 0 ]; then
  echo "::error::Filtered LCOV has zero instrumented lines (check exclude rules / input)" >&2
  exit 1
fi

PCT=$(awk -v lh="$LH" -v lf="$LF" 'BEGIN { printf "%.2f", lh * 100 / lf }')

echo "Frontend line coverage (excluding generated): ${LH}/${LF} (${PCT}%)"
echo "  input:    $INPUT"
echo "  filtered: $OUTPUT"
echo "  excluded: lib/generated/**, lib/l10n/app_localizations*.dart"

if [ -n "$THRESHOLD" ]; then
  awk -v c="$PCT" -v t="$THRESHOLD" 'BEGIN {
    if (c + 0 < t + 0) {
      printf "::error::Coverage %s%% is below threshold %s%%\n", c, t
      exit 1
    }
    print "OK (threshold " t "%)"
  }'
fi
