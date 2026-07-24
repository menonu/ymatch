# Architecture Decision Records (ADRs)

This directory holds the project's **Architecture Decision Records** — immutable, dated records of significant architectural decisions, the context that led to them, and their consequences.

ADRs live under the **Explanation** genre of the Diátaxis framework: they exist to explain *why* the system is shaped the way it is, not to prescribe steps (that is the job of How-To guides) or describe current state (that is the job of Reference docs).

---

## When to write an ADR

Write an ADR whenever a decision is **significant and hard to reverse** — for example:

- Choosing a framework, library, data store, or serialization format.
- Defining a cross-cutting pattern (e.g. repository shape, error-handling strategy, auth model).
- A structural refactor that changes how subsystems communicate.
- A decision to *not* adopt a technology or pattern.
- A decision that supersedes a prior ADR.

Trivial, easily-reversed choices (a one-line config, a small refactor within a single file) do **not** need an ADR — capture them in the PR description or a commit message instead.

## Naming & numbering

- File name: `NNNN-kebab-case-title.md`, where `NNNN` is a zero-padded, monotonically increasing sequence number (e.g. `0001-repository-concrete-struct.md`).
- Always take the **next free number** — never reuse or renumber an existing ADR.
- The decision date goes inside the document, not the file name.

## Document structure

Each ADR follows this template:

```markdown
# ADR NNNN: <Title>

- **Status**: Proposed | Accepted | Superseded by [ADR MMMM](MMMM-...) | Deprecated
- **Date**: YYYY-MM-DD
- **Supersedes**: [ADR LLLL](LLLL-...) (optional — present only when this ADR replaces an earlier one)

## Context
The forces at play, the problem we are trying to solve, and the relevant constraints. State the situation *as it was at decision time* — do not back-fit later knowledge.

## Decision
The change we are making or the option we are choosing, stated clearly and unambiguously.

## Consequences
The resulting trade-offs: what becomes easier, what becomes harder, follow-up work that is now required, and any risks accepted.

## Alternatives Considered
Other options that were seriously evaluated and why they were not chosen.
```

## Workflow — ADRs are append-only

ADRs are **never edited in place** once their decision is made. To change or reverse a decision:

1. **Create a new ADR** with the next free number describing the new decision.
2. In the new ADR, set **Status** to `Accepted` and add a `Supersedes:` line linking to the old one.
3. In the **old** ADR, change **Status** to `Superseded by [ADR NNNN](NNNN-...)` (and link forward). Do **not** rewrite or delete the old ADR's body — its `Context` / `Decision` / `Consequences` must remain a faithful record of what was decided at the time.

Record every ADR in the index below, newest last.

## Stability & references

Accepted ADRs are **historical decision records**, not living design docs. Architecture docs under `docs/explanation/architecture/` may track the current tree; ADRs must not.

### Freeze (accepted ADRs)

Once **Status** is `Accepted` (or later Superseded / Deprecated), the ADR body is **frozen**.

**Do not** edit accepted ADRs for:

- code renames, module splits, or path moves
- “bring the narrative up to date with the current tree”
- behavior or decision changes (those need a **new** ADR that supersedes)

**Allowed exceptions** (narrow):

| Exception | Scope |
|-----------|--------|
| **Status** line only | When superseding (append-only workflow above) |
| Index table in this `README.md` | Add/update ADR rows |
| Pure typos / broken relative links to other docs or ADRs | Must **not** change decision meaning |
| One-time path cleanup | Explicit exception for issue-driven mechanical cleanup of fragile locations (no meaning change) |

Do **not** treat formatting or “cleanup” as a license to rewrite paths, module names, or narrative after every refactor.

### No concrete source locations

In new ADRs (and in any one-time cleanup of older ones), prefer stable concept names and Diátaxis links over filesystem paths and line anchors:

| Prefer | Avoid |
|--------|--------|
| Component / type / permission names (`MatchRepository`, `merch.create`) | `backend/src/repositories/match_.rs` |
| Behavioral description (“periodic matcher”) | `src/matching.rs:15` |
| Links to architecture docs / other ADRs | Markdown links into `backend/src/...` or `frontend/lib/...` |
| Table / API / proto field names | `file.rs:line-line` spans |

If a decision was motivated by a specific code shape at the time, describe it in prose (“the merch create handler had no authz gate”) rather than pinning a path that will move.

Migrations, issue numbers, and API routes (`POST /api/v1/...`) are fine when they identify a stable product or schema contract — they are not source-tree locations.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](0001-match-scoped-to-item-group.md) | Matches Are Scoped to a Single Item Group | Accepted | 2026-06-29 |
| [0002](0002-negotiation-state-machine.md) | Balanced Negotiation State Machine | Superseded in part by [0009](0009-apply-inventory-decrements-giver-have.md) | 2026-06-29 |
| [0003](0003-subset-woff2-japanese-font.md) | Subset WOFF2 Japanese Font Bundled in Repo | Accepted | 2026-07-01 |
| [0004](0004-rbac-permission-model.md) | Role-Based Access Control (RBAC) Permission Model | Accepted | 2026-07-05 |
| [0005](0005-merch-create-permission.md) | Gate Merch Creation Behind `merch.create` | Accepted | 2026-07-08 |
| [0006](0006-derive-user-role-from-user-roles.md) | Derive `User.role` from `user_roles` at Read Time (drop `users.role` mirror) | Accepted | 2026-07-10 |
| [0007](0007-inventory-export-text-formats.md) | Client-Side Inventory Export with Text Formats | Accepted | 2026-07-13 |
| [0008](0008-merchandise-deletion-semantics.md) | Merchandise Deletion Semantics and the `CANCELLED` Match Status | Accepted (UI visibility of `CANCELLED` revised in part by [0010](0010-inventory-mutual-capacity-invalidation.md); catalog visibility of soft-deleted merch revised in part by [0011](0011-hide-deleted-merch-from-catalog.md)) | 2026-07-14 |
| [0009](0009-apply-inventory-decrements-giver-have.md) | Apply Inventory Decrements Giver HAVE by Default | Accepted (TRADE clamp superseded in part by [0014](0014-fail-closed-inventory-apply.md)) | 2026-07-15 |
| [0010](0010-inventory-mutual-capacity-invalidation.md) | Inventory Mutual-Capacity Invalidation and Visible `CANCELLED` | Accepted | 2026-07-17 |
| [0011](0011-hide-deleted-merch-from-catalog.md) | Hide Soft-Deleted Merchandise from Catalog Surfaces by Default | Accepted | 2026-07-18 |
| [0012](0012-rematch-after-reject-or-cancel.md) | Rematch After Reject or Cancel (Reopen PENDING with Prior-History Annotation) | Accepted | 2026-07-18 |
| [0013](0013-group-scope-rbac.md) | Group-Scoped RBAC (`scope_type = 'group'`) | Accepted | 2026-07-21 |
| [0014](0014-fail-closed-inventory-apply.md) | Fail-Closed TRADE Capacity (HAVE Optional) | Accepted | 2026-07-22 |
