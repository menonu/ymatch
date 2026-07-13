# ADR 0007: Client-Side Inventory Export with Text Formats

- **Status**: Accepted
- **Date**: 2026-07-13

## Context

Users maintain per-item-group inventory in three statuses — 所持 (HAVE), 求 (WANT), 譲 (TRADE) — and want to **export their own counts within a single item group** so they can paste them into external tools (spreadsheets, trading checklists, etc.). The export must:

- Be **text-based only** (no binary formats) — easy to copy, paste, and diff.
- Let the user pick **which of 所持 / 求 / 譲 to include** via checkboxes.
- Offer **several selectable output formats**, all text.

The canonical "basic" format, from the feature request, is:

```
所持: a*2, b*3, c
求: d, e*2
譲: a, b*2
```

i.e. one line per status, `name*qty` with the `*qty` suffix omitted when the quantity is 1, items separated by `, `.

Two architectural questions needed resolving before any code:

1. **Where is the text rendered?** A new backend `text/plain` endpoint, or purely in the Flutter client?
2. **What is the format grammar and the label/token vocabulary**, so the output is stable and diff-friendly?

The inventory data the export needs is **already fetched by the client**: `GET /api/v1/user/:id/inventory` returns every `InventoryItem` joined with `merch_name` and `group_name`. The labels 所持 / 求 / 譲 already exist as localized strings in the frontend (`.arb` keys `have` / `want` / `trade`). The export action is a user-initiated **copy-to-clipboard** from the group screen, not a programmatic API consumed by other services.

## Decision

**Export is rendered client-side in the Flutter app. No backend, proto, or DB changes.**

The feature is a pure function of already-available data plus user choices (selected group, selected statuses, selected format). Keeping it client-side:

- Leaves the inventory/label data flow untouched — no new endpoint, no proto message, no migration.
- Keeps the **single source of label truth** in the existing `.arb` localizations; the Rust backend never needs to know the display strings for HAVE/WANT/TRADE (it returns canonical status tokens today and localizes nowhere).
- Matches the interaction: the user picks checkboxes + a format in the UI and copies the result. There is no external caller that would benefit from a stable, curl-able URL.

### Format set

Three text formats ship initially, selected via a format chooser in the UI. The set is open-ended — adding a format later is additive and does not require an ADR.

1. **`basic`** — the canonical format above. One line per included status, in the fixed order 所持 → 求 → 譲. Each line: `<label>: <items>`. Items are `name` or `name*qty` (qty suffix omitted when qty == 1), comma-space separated, **sorted alphabetically by name** for stable diffs. Omit a status's line entirely when its checkbox is unchecked.

2. **`csv`** — RFC 4180 CSV with header `status,item,quantity`, one row per item. Fields are quoted when they contain a comma, quote, or newline. Status column uses the **localized label** (所持 / 求 / 譲), consistent with `basic`. Rows ordered status-first (所持 → 求 → 譲), then alphabetically by name.

3. **`markdown`** — a single GitHub-flavored table:

   ```
   | status | item | qty |
   |--------|------|-----|
   | 所持   | a    | 2   |
   | 所持   | b    | 3   |
   ...
   ```

   Same row ordering as CSV; the `qty` cell is the integer.

### Rules shared by all formats

- **Scope**: a single item group (`(event_id, group_name)`). Items whose `group_name` does not match are excluded. Exporting across multiple groups is not supported in this ADR.
- **Quantity 0 / negative rows are excluded** — matches the matching engine, which only ever considers `quantity > 0` (`repositories/match_.rs`, `matching.rs`). This avoids `a*0` noise.
- **Quantity 1** is emitted as bare `name` in `basic`; CSV and markdown emit the literal `1` so their columns stay numeric.
- **Status ordering** is fixed: 所持, 求, 譲, regardless of checkbox order.
- **Labels** come from the existing `have` / `want` / `trade` `.arb` keys, so the export is localized the same way the rest of the inventory UI is.
- **Empty selection** (no status checked) yields an empty string for `basic`, a header-only CSV, and a header-only markdown table — the export action is still allowed and copies that.

### Tests

Following the project TDD convention, the formatting logic lives in a pure Dart function (input: inventory items + selection + format → `String`) with **unit tests under `frontend/test/`** covering: qty-1 suffix omission, qty-0 exclusion, checkbox filtering, alphabetical ordering, CSV quoting of commas/quotes, and the empty-selection edge. A widget test verifies the chooser + copy-to-clipboard UX on the group screen.

## Consequences

- **Positive**: No backend/proto/migration churn; labels stay in one place; the export is trivially testable as a pure function; adding a format is additive and low-risk.
- **Negative**: The format logic lives only in the Flutter client. A future second consumer (a separate CLI, a web scraper, another mobile client) would have to reimplement it — but there is only one client today (Flutter, web + mobile share the same Dart), so this is theoretical.
- **Negative**: There is no stable server URL for the export, so it cannot be fetched programmatically by an external tool — by design, since the trigger is a human copy action. If a programmatic export API is ever needed, it becomes a **new** ADR (additive backend endpoint); it does not reverse this one.
- **Follow-up**: A GitHub issue drives the implementation (Issue → Branch → TDD → PR per the development workflow). Localization of any new UI strings (format names, checkbox labels, "copied" toast) is added to `app_en.arb` + `app_ja.arb` and regenerated via `flutter gen-l10n`.

## Alternatives Considered

- **Backend `text/plain` export endpoint** (`GET /api/v1/events/:id/groups/:group_name/export?user_id=&statuses=&format=`): rejected for now. It would give a stable, curl-able URL and a single Rust source of truth, but it duplicates the HAVE/WANT/TRADE display labels into the backend (which today localizes nothing), forces a proto message for the request, and serves no current consumer — the only caller is the Flutter UI doing a copy-to-clipboard. It remains a clean future option as an additive ADR if a programmatic consumer appears.

- **One canonical format only (no chooser)**: rejected — the request explicitly asks for several selectable text formats; different external tools prefer different shapes (a trading checklist wants `basic`, a spreadsheet wants `csv`).

- **Canonical English tokens (HAVE/WANT/TRADE) instead of localized labels in the output**: rejected for the `basic` format because the request's example uses 所持 / 求 / 譲, and the feature targets the JP merchandise-trading ecosystem. CSV/markdown reuse the same localized labels for consistency rather than mixing vocabularies. If a locale-neutral machine format is later needed, it can be added as an additional format without changing these.