# ymatch Architecture (arc42)

Living architecture documentation for **ymatch**, structured as a pragmatic
[arc42](https://arc42.org/) subset. It explains *why the system is shaped the
way it is* and *how the major parts fit together*.

| This docs set is… | It is not… |
|-------------------|------------|
| **Explanation** (Diátaxis) | A deploy runbook (→ [How-To](../../how_to/oci_deployment.md)) |
| Current on `main` | A frozen design proposal |
| Linked to ADRs for decisions | A replacement for ADRs |

Significant hard-to-reverse choices live in
[Architecture Decision Records](../adr/README.md). This tree summarizes the
resulting shape and points outward for details.

## Section map

| # | Section | Contents | Notation |
|---|---------|----------|----------|
| 01 | [Introduction & goals](01-introduction.md) | Product goals, stakeholders, top requirements | prose |
| 02 | [Constraints](02-constraints.md) | Technical, organizational, operational limits | prose |
| 03 | [Context & scope](03-context.md) | External actors and system boundary | **C4** (D2 → SVG) |
| 04 | [Solution strategy](04-solution-strategy.md) | Tech stack, patterns, ADR index | prose |
| 05 | [Building blocks](05-building-blocks.md) | Backend layers, frontend layers, matching job | **C4** (D2 → SVG) |
| 06 | [Runtime view](06-runtime.md) | Auth, matching, trade negotiation, inventory apply | D2 → SVG |
| 07 | [Deployment view](07-deployment.md) | Local, staging, production | **C4** (D2 → SVG) |
| 08 | [Cross-cutting](08-crosscutting.md) | Security, RBAC, i18n, errors, images | prose + links |
| 09 | [Quality](09-quality.md) | Quality attributes (SAiP 4th vocabulary), testing, performance | prose |

## Related docs

| Genre | Where |
|-------|--------|
| API / DB / permissions / UI | [`docs/reference/`](../../reference/api_spec.md) |
| Deploy, secrets, roles, e2e | [`docs/how_to/`](../../how_to/oci_deployment.md) |
| Repo security policy | [`security.md`](../security.md) |
| Disaster recovery lessons | [`disaster_recovery.md`](../disaster_recovery.md) |
| ADRs | [`adr/`](../adr/README.md) |

## Conventions used here

- **C4 model** ([c4model.com](https://c4model.com/)) for structural views in
  sections 03, 05, and 07.
- **Diagrams** are authored in [D2](https://d2lang.com/) and **committed as SVG**
  under [`diagrams/`](diagrams/) (paired `.d2` source + `.svg` output). GitHub’s
  Mermaid renderer does not reliably draw C4; do not use Mermaid for these views.
  Regenerate after editing a `.d2` file:
  ```bash
  # requires: https://d2lang.com/tour (d2 CLI)
  d2 --layout=dagre docs/explanation/architecture/diagrams/FOO.d2 \
                    docs/explanation/architecture/diagrams/FOO.svg
  ```
  Or rebuild all: `for f in docs/explanation/architecture/diagrams/*.d2; do d2 --layout=dagre "$f" "${f%.d2}.svg"; done`
- Prefer **links** over copying reference material (endpoint lists, column
  definitions, permission matrices).
- Prefer **accuracy over completeness** — empty arc42 sections are omitted rather
  than filled with placeholders.
- When code and this doc disagree, **code + ADRs win**; open a PR to fix the doc.
