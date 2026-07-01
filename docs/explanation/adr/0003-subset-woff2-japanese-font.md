# ADR 0003: Subset WOFF2 Japanese Font Bundled in Repo

- **Status**: Accepted
- **Date**: 2026-07-01

## Context

The frontend web bundle ships a Japanese font so that kanji/kana render in a
consistent JP style on every client — most importantly on Android browsers
without a Japanese system font, where the absence of a bundled font causes a
*中華フォント* (CJK glyph mismatch) regression (see #291, which introduced the
bundling).

#291 bundled the **full** Noto Sans JP as a raw `NotoSansJP-Regular.ttf`
(~5.3 MB, every kanji). Because the file is large, it was kept out of the repo:
it is gitignored and fetched at build time from the Google Fonts CDN by
`scripts/download_font.sh` — in the prod Dockerfile and in three CI workflows.
Flutter Web's CanvasKit renderer does not consume CSS `<link>` fonts; it needs
the font file registered via the engine and present in the asset bundle.

#353 measured the prod web first-load at ~12.6 MB (SkWasm/Wimp) to ~16.3 MB
(CanvasKit), served uncompressed. The bundled font alone is ~33–42% of that
transfer — by far the largest app-controllable asset. The build-time download
also adds per-worktree friction: a fresh checkout needs the download step
before `flutter run` / `flutter test` work.

We need to keep bundling the font (no change to the rendering approach) but
shrink it dramatically and remove the build-time download friction.

## Decision

Replace the full gitignored TTF with a **committed subset WOFF2** of Noto Sans
JP, ~1.5 MB, with font metadata (kerning, etc.) retained:

- Commit `frontend/fonts/NotoSansJP-Regular.woff2` to the repo.
- Use the pre-built subset from
  [`ixkaito/NotoSansJP-subset`](https://github.com/ixkaito/NotoSansJP-subset)
  (`subset/` variant, OFL-1.1 — redistribution permitted), pinned to commit
  `5ef59a7ff1a63a3695e3856ef4de18382879f913`
  (sha256 `5cde484837284884893a57abae401355cbd9294ea45d584f3e22e0e1d8cbeacf`).
  The glyph set covers Basic Latin, Latin-1 punctuation, JIS Level 1/2/3 kanji,
  kana, and common symbols.
- Declare the `.woff2` asset under the `NotoSansJP` family in `pubspec.yaml`
  (Flutter 3.44 supports declaring a `.woff2` font asset).
- Delete `scripts/download_font.sh` and its invocation in
  `frontend.Dockerfile.prod` and the three CI workflows. The font now reaches
  the build via `COPY frontend ./` (Docker) and the repo checkout (CI / local).

`lib/theme/app_theme.dart` is unchanged — `fontFamily: 'NotoSansJP'` still
resolves to the bundled font.

## Consequences

- **Smaller first-load**: the font drops from ~5.3 MB to ~1.5 MB (~3.7 MB
  saved, ~3.5x smaller), the single biggest app-controllable win available.
- **No build-time font download**: local `flutter run` / `flutter test` work in
  a fresh worktree with no extra step; the Docker build and CI shed the
  download step and the CDN dependency at build time.
- **Binary committed to the repo**: ~1.5 MB of binary now lives in git history.
  This is accepted because it is well under the "binary in repo" pain threshold
  and removes more friction than it adds.
- **Fixed glyph set**: the subset covers JIS Level 1/2/3 kanji + kana + ASCII +
  symbols. Any UI text using a kanji outside that set would fall back to the
  client's system font for that glyph (a re-subset would be needed to cover it).
  This is a real but low-probability constraint given the app's JP vocabulary.
- **Third-party binary, pinned**: we trust ixkaito's pre-built subset rather
  than generating our own. It is pinned by commit SHA + sha256 in this ADR.
  Re-subsetting (e.g. to change the glyph set) is not part of this change; if
  needed later, adopt the `pyftsubset` self-generation alternative below.
- **Accepted ~1.5 MB over the issue's ~1 MB estimate**: the `subset/` variant
  retains metadata (kerning) to avoid any *中華フォント*/quality regression of
  #291; the smaller `subset-min/` strips metadata and was rejected on those
  grounds. The `<1 MB` figure in #353 was an estimate, not a hard limit.

## Alternatives Considered

- **`subset-min/` variant (~0.5 MB)** from the same repo. Smaller and would
  meet the issue's `<1 MB` estimate, but it strips font metadata (kerning) — a
  risk against the #291 quality concern. Rejected in favour of the
  metadata-retaining `subset/` variant.
- **Self-generate the subset with `pyftsubset`** (FontTools), as originally
  suggested in #353 (`scripts/subset_font.sh`). Fully reproducible and lets us
  control the glyph set, but adds a Python + FontTools maintainer toolchain
  dependency for a one-off task. Not adopted now; can be taken up later if the
  glyph set needs to change (the committed WOFF2 can be regenerated and
  re-committed without changing this ADR's decision).
- **Enable gzip/brotli compression on the prod server** (Option B in #353).
  Independent of the font and orthogonal — it would compress `main.dart.js`
  and the renderer `.wasm` too. Tracked separately as a follow-up; it stacks
  with this change rather than substituting for it.