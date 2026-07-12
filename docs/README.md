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
* [Granting Global Roles](how_to/grant_roles.md): Run `scripts/grant_role.sh <username> <role>` per environment to grant `user`/`moderator`/`admin` (ADR 0004 §6, #228) without committing a username.
* [OCI Production Deployment (Always Free ARM)](how_to/oci_deployment.md): Steps to provision infrastructure with Terraform and deploy the full stack on OCI.
* [Applying Terraform with Secrets (TF_VAR_ + .env)](how_to/terraform_apply.md): Run `terraform plan`/`apply` for the newrelic + oci modules without committing secrets or host identifiers (#284).
* [OCI Credentials Management](how_to/oci_credentials.md): API key generation, rotation, and loss-recovery procedure for the RSA 2048 key used by Terraform and the OCI CLI.
* [Monitoring Setup Guide](how_to/monitoring_setup.md): Setup and queries for New Relic application/infrastructure alerts and monitoring.
* [GCP Historical Deployment](how_to/cloud_deployment.md): Historical GCP deployment strategy (all GCP app services stopped; DB backups moved to OCI Object Storage in #383).
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

* [Repository Security](explanation/security.md): What must never be committed (secrets, credentials, host paths, PII, terraform state), where sensitive values live instead, and the pre-commit checklist. Governing policy for a public repo.
* [Requirements Specification](explanation/requirements.md): Functional and non-functional requirements of the system.
* [System Architecture & Actors](explanation/architecture.md): Overview of components, tech stack, and roles (User, System).
* [Use Cases](explanation/use_cases.md): User interaction flows, triggers, goals, and pre-conditions.
* [Initial Project Idea](explanation/initial_concept.md): Original prompt, core matching rules, and initial requirements definition.
* [Disaster Recovery](explanation/disaster_recovery.md): Recovery procedure, lessons learned from the June 2026 end-to-end test, and known gaps.
* [Phase 4 Design](explanation/refactoring_phase_4.md): Match/Inventory/Message repository design, N+1 fix (1+4N → 3 queries), state-machine model for the trade lifecycle. Historical (describes the initial `trait + dyn` shape that #191 refined — see [Issue #191](https://github.com/menonu/ymatch/issues/191) for the current shape).
* [Backend Refactoring Summary](explanation/refactoring_summary.md): Phase 1-5 wrap-up of the #163 Repository pattern refactor, final architecture, aggregate metrics, follow-up issues. The post-#191 follow-up (PRs #192-#210, closing the `trait + dyn` indirection in favor of a concrete-struct + generic-Executor shape) is documented on [Issue #191](https://github.com/menonu/ymatch/issues/191) (closing comment).
* [Architecture Decision Records](explanation/adr/README.md): Conventions and index for ADRs — append-only records of significant architectural decisions. Supersede old ADRs with a new ADR rather than editing them in place.
