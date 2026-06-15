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

* [Developer Quickstart](file:///home/menonu/ws/ymatch/docs/tutorials/developer_quickstart.md): Walkthrough of database setup, tests, and running backend & frontend servers locally.

---

## 2. How-To Guides (Task-Oriented)
Direct, action-oriented instructions to solve specific problems or accomplish key deployment/operation tasks.

* [Development Workflow Guide](file:///home/menonu/ws/ymatch/docs/how_to/development_workflow.md): Step-by-step workflow for branches, pull requests, local lints, and tests.
* [OCI Production Deployment (Always Free ARM)](file:///home/menonu/ws/ymatch/docs/how_to/oci_deployment.md): Steps to provision infrastructure with Terraform and deploy the full stack on OCI.
* [OCI Credentials Management](file:///home/menonu/ws/ymatch/docs/how_to/oci_credentials.md): API key generation, rotation, and loss-recovery procedure for the RSA 2048 key used by Terraform and the OCI CLI.
* [Monitoring Setup Guide](file:///home/menonu/ws/ymatch/docs/how_to/monitoring_setup.md): Setup and queries for New Relic application/infrastructure alerts and monitoring.
* [GCP Historical Deployment](file:///home/menonu/ws/ymatch/docs/how_to/cloud_deployment.md): Historical GCP backup & deployment strategy (GCP services are currently stopped except for backup bucket storage).

---

## 3. Reference Guides (Information-Oriented)
Fact-based, technical specifications describing the machinery, endpoints, schemas, and configurations of the system.

* [API Specification](file:///home/menonu/ws/ymatch/docs/reference/api_spec.md): REST endpoints, request/response formats, parameters, and headers.
* [Database Schema](file:///home/menonu/ws/ymatch/docs/reference/db_schema.md): Database tables, fields, constraints, indexes, and entity-relationship mapping.
* [UI Specifications](file:///home/menonu/ws/ymatch/docs/reference/ui_specs.md): Layout structures, screens, navigation specs, and views.
* [UI Components Reference](file:///home/menonu/ws/ymatch/docs/reference/ui_components.md): Component identifiers for screens, dialogs, cards, forms, and providers.

---

## 4. Explanation (Understanding-Oriented)
Conceptual explanations, architecture reviews, design decisions, and background context to clarify *why* the system is designed the way it is.

* [Requirements Specification](file:///home/menonu/ws/ymatch/docs/explanation/requirements.md): Functional and non-functional requirements of the system.
* [System Architecture & Actors](file:///home/menonu/ws/ymatch/docs/explanation/architecture.md): Overview of components, tech stack, and roles (User, System).
* [Use Cases](file:///home/menonu/ws/ymatch/docs/explanation/use_cases.md): User interaction flows, triggers, goals, and pre-conditions.
* [Initial Project Idea](file:///home/menonu/ws/ymatch/docs/explanation/initial_concept.md): Original prompt, core matching rules, and initial requirements definition.
* [Disaster Recovery](file:///home/menonu/ws/ymatch/docs/explanation/disaster_recovery.md): Recovery procedure, lessons learned from the June 2026 end-to-end test, and known gaps.
* [Phase 4 Design](file:///home/menonu/ws/ymatch/docs/explanation/refactoring_phase_4.md): Match/Inventory/Message repository design, N+1 fix (1+4N → 3 queries), state-machine model for the trade lifecycle. Historical (describes the initial `trait + dyn` shape that #191 refined — see [Issue #191](https://github.com/menonu/ymatch/issues/191) for the current shape).
* [Backend Refactoring Summary](file:///home/menonu/ws/ymatch/docs/explanation/refactoring_summary.md): Phase 1-5 wrap-up of the #163 Repository pattern refactor, final architecture, aggregate metrics, follow-up issues. The post-#191 follow-up (PRs #192-#210, closing the `trait + dyn` indirection in favor of a concrete-struct + generic-Executor shape) is documented on [Issue #191](https://github.com/menonu/ymatch/issues/191) (closing comment).
* [Test Suite Audit](file:///home/menonu/ws/ymatch/docs/explanation/test_audit.md): Inventory of all backend and frontend tests, categorized by pyramid/trophy layer, with current proportions and target recommendations. Phase 1 deliverable of #185.
