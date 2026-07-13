# ymatch Documentation Index

This directory contains the documentation for the `ymatch` merchandise trading platform, structured according to the **Diátaxis documentation framework**.

The documentation is organized into four distinct genres based on their purpose and audience:

```
                  ┌───────────────────────────────┐
                  │          DOCUMENTATION        │
                  └───────────────────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
  ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
  │  TUTORIALS  │          │   HOW-TO    │          │  REFERENCE  │
  │  (Learning) │          │   (Tasks)   │          │ (Technical) │
  └─────────────┘          └─────────────┘          └─────────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  ▼
                           ┌─────────────┐
                           │ EXPLANATION │
                           │ (Concept)   │
                           └─────────────┘
```

---

## 1. Tutorials (Learning-Oriented)
Practical steps to help you get started and learn how to develop with `ymatch`.

* [Developer Quickstart](tutorials/developer_quickstart.md): Walkthrough of database setup, tests, and running backend & frontend servers locally.

---

## 2. How-To Guides (Task-Oriented)
Direct, action-oriented instructions to solve specific problems or accomplish key deployment/operation tasks.

* [Development Workflow Guide](how_to/development_workflow.md): Step-by-step workflow for branches, pull requests, local lints, and tests.
* [PR Review Guide](how_to/pr_review.md): Rubric, methodology, severity tags, and comment format for reviewing PRs (pairs with project skill `.claude/skills/pr-review/`).
* [Granting Global Roles](how_to/grant_roles.md): Run `scripts/grant_role.sh <username> <role>` per environment to grant `user`/`moderator`/`admin` (ADR 0004 §6, #228) without committing a username.
* [OCI Production Deployment (Always Free ARM)](how_to/oci_deployment.md): Steps to provision infrastructure with Terraform and deploy the full stack on OCI.
* [Applying Terraform with Secrets (TF_VAR_ + .env)](how_to/terraform_apply.md): Run `terraform plan`/`apply` for the newrelic + oci modules without committing secrets or host identifiers (#284).
* [OCI Credentials Management](how_to/oci_credentials.md): API key generation, rotation, and loss-recovery procedure for the RSA 2048 key used by Terraform and the OCI CLI.
* [Monitoring Setup Guide](how_to/monitoring_setup.md): Setup and queries for New Relic application/infrastructure alerts and monitoring.
* [Frontend-Driven E2E Tests](how_to/e2e_tests.md): How to run the wire-contract E2E test suite introduced in #213 (drives the real `ApiClient` + proto3 JSON against a docker-compose stack).

---

## 3. Reference Guides (Information-Oriented)
Fact-based, technical specifications describing the machinery, endpoints, schemas, and configurations of the system.

* [API Specification](reference/api_spec.md): REST endpoints, request/response formats, parameters, and headers.
* [Database Schema](reference/db_schema.md): Database tables, fields, constraints, indexes, and entity-relationship mapping.
* [RBAC Permissions Reference](reference/permissions.md): Catalog of every RBAC role and permission — scope, granting roles, `*.any` overlap, and the handler that enforces each (ADR 0004 / 0005).
* [UI Specifications](reference/ui_specs.md): Layout structures, screens, navigation specs, and views.
* [UI Components Reference](reference/ui_components.md): Component identifiers for screens, dialogs, cards, forms, and providers.

---

## 4. Explanation (Understanding-Oriented)
Conceptual explanations, architecture reviews, design decisions, and background context to clarify *why* the system is designed the way it is.

* [Architecture (arc42)](explanation/architecture/README.md): Living system architecture — goals, constraints, **C4** L1 context (§03), L2–L3 containers/components (§05), deployment (§07), runtime scenarios, cross-cutting concerns, quality.
* [Architecture Decision Records](explanation/adr/README.md): Conventions and index for ADRs — append-only records of significant architectural decisions. Supersede old ADRs with a new ADR rather than editing them in place. Linked from the arc42 solution-strategy section.
* [Repository Security](explanation/security.md): What must never be committed (secrets, credentials, host paths, PII, terraform state), where sensitive values live instead, and the pre-commit checklist. Governing policy for a public repo.
* [Disaster Recovery](explanation/disaster_recovery.md): Recovery procedure, lessons learned from the June 2026 end-to-end test, and known gaps.
