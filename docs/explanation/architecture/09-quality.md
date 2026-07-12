# 09 — Quality requirements

## Quality goals

| Priority | Quality goal | How we approach it |
|----------|--------------|--------------------|
| 1 | **Correct trades** | Lifecycle pure guards + DB transactions; integration tests for offer/accept/apply; e2e for wire contract. |
| 2 | **Safe authz** | RBAC checks on privileged handlers; permission reference + ADRs; role-grant script for ops. |
| 3 | **Operable on a small budget** | Single-VM compose, documented DR, backups to Object Storage. |
| 4 | **Contributor safety** | Public-repo secret policy; CI fmt/clippy/analyze/tests; coverage gates. |
| 5 | **Usable i18n UI** | EN/JA localizations; font subsetting ADR. |

## Testing strategy

Aligned with Practical Test Pyramid (backend) and Testing Trophy emphasis
(frontend integration/widget/provider), without a separate audit doc:

| Layer | Backend | Frontend |
|-------|---------|----------|
| Static | `cargo fmt`, `clippy -D warnings` | `flutter analyze` |
| Unit | `#[cfg(test)]` in modules (lifecycle guards, RBAC, rate limit, …) | providers, utils, pure helpers |
| Integration | `backend/tests/*` against real Postgres | widget tests with overridden providers |
| E2E | (via Flutter wire tests) | `frontend/test/e2e/*` + `integration_test/*` against compose stack |

Commands (see root Taskfile / [developer quickstart](../../tutorials/developer_quickstart.md)):

```bash
task test                 # aggregate
task backend:test
task frontend:test        # excludes e2e tags locally when configured
```

Coverage workflows: backend line-coverage gate on `main`; frontend coverage
workflow exists for visibility.

## Performance notes

- Match list path batches related rows (historical N+1 fix in match repository).
- Matcher is periodic, not per-request — acceptable for event-day scale of a
  single Always Free VM.
- Flutter web first-load is dominated by engine + font; subset font ADR reduces
  transferable size vs full Noto.

## Known quality gaps (living list)

Document honestly; track work in GitHub issues rather than expanding this into
a backlog dump:

- Push notifications are **stubbed** (`notifications.rs` logs only).
- Some operational runbooks assume maintainer familiarity with OCI free-tier
  quotas (see disaster recovery lessons).

Update this subsection when a gap is closed or a new systemic risk appears.
