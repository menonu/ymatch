# 09 — Quality requirements

Quality attributes use the vocabulary from *Software Architecture in Practice*
(4th ed., Bass / Clements / Kazman): **Availability**, **Deployability**,
**Interoperability**, **Modifiability**, **Performance**, **Security**,
**Testability**, **Usability**, and related attributes as needed. Functionality
(correct trade rules) is specified in [01 — Introduction](01-introduction.md)
and ADRs; this chapter focuses on *how well* the system achieves qualities.

## Quality goals

| Quality attribute | Goal for ymatch | How we approach it |
|-------------------|-----------------|--------------------|
| **Testability** | Trade and API behavior can be verified cheaply and repeatedly. | Lifecycle pure guards + DB transactions; unit tests for state-machine rules; integration tests for offer/accept/apply; e2e for the wire contract. |
| **Security** | Confidentiality of secrets; authorization of privileged actions; integrity of trades under RBAC. | Public-repo secret policy ([security.md](../security.md)); `RbacService` checks; permission reference + ADRs; rate limiting; role-grant script for ops. |
| **Usability** | Fans and curators can complete inventory/trade flows on event day, in EN/JA. | Flutter web UI; Riverpod state; EN + JA localizations; subset JP font ([ADR 0003](../adr/0003-subset-woff2-japanese-font.md)). |
| **Deployability** | Staging/prod deployable as a small, repeatable stack; local dev is one compose + cargo/flutter. | Identical `docker-compose.oci.yml` per VM; GitHub Actions deploy; Terraform for infra; [OCI how-tos](../../how_to/oci_deployment.md). |
| **Availability** | **≥ 98%** uptime for the production environment. | **Monitoring** (New Relic / alerts — [monitoring_setup](../../how_to/monitoring_setup.md)) to detect and respond to outages; health/status endpoints. **No service redundancy** (single VM + Compose stack per environment by design — Always Free cost envelope). Object Storage backups; [disaster_recovery](../disaster_recovery.md) for VM/key loss. |
| **Performance** | Match lists and API remain usable under modest concurrent event-day load on one VM. | Batched match-list queries (historical N+1 fix); periodic matcher (not per-request); keep first-load assets bounded (font subset). |
| **Modifiability** | Domain and infra changes land via small PRs without rewriting the stack. | Handler / service / repository layering; concrete repositories; append-only ADRs; protobuf as the shared contract. |
| **Interoperability** | Client and server share one explicit data contract. | `proto/models.proto` → generated Rust + Dart; REST under `/api/v1` ([API spec](../../reference/api_spec.md)). |

## Testing strategy (supports Testability)

Aligned with the Practical Test Pyramid (backend) and Testing Trophy emphasis
(frontend integration / widget / provider):

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

- Push notifications are **stubbed** (`notifications.rs` logs only) — limits
  **usability** for “notify me when matched” until a real provider lands.
- Some operational runbooks assume maintainer familiarity with OCI free-tier
  quotas (see disaster recovery lessons) — **availability** / ops friction.

Update this subsection when a gap is closed or a new systemic risk appears.
