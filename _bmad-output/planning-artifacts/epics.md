---
stepsCompleted: ['step-01-validate-prerequisites', 'step-02-design-epics', 'step-03-create-stories', 'step-04-final-validation']
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/project-context.md
project_name: 'kw-platform-ops'
user_name: 'Jordi'
date: '2026-05-07'
completedAt: '2026-05-07'
status: 'complete'
---

# kw-platform-ops - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for kw-platform-ops, decomposing the requirements from the PRD and Architecture into implementable stories. (No UX Design document exists for this project — `kw-platform-ops` is a platform-engineering reference repository with no significant UI surface; the Flask onboarding webapp is a thin operator UI per project-context.md.)

## Requirements Inventory

### Functional Requirements

#### Local Bootstrap & Environment

FR1: A Solutions Engineer can clone the repository to a clean macOS environment and bring the full local execution stack (state backend, Actions runner, helper services) to a runnable state via a single Make target.
FR2: The repository provides an S3-compatible Terraform state backend that runs locally without requiring any cloud-infrastructure account.
FR3: The repository provides a GitHub Actions runner environment compatible with executing every platform workflow via `act` on macOS, end-to-end, without manual hand-edits.
FR4: The repository declares all required local dependencies (container runtime, `act`, Terraform, Helm, kubectl, decK, Spectral, etc.) and produces an actionable error message when any are missing or out-of-version.
FR5: An operator can start, stop, and reset the local execution environment to a clean state via documented Make targets.
FR6: An operator can configure the only required external credential — a Konnect access token — through a single gitignored local secrets file, without modifying any tracked source.

#### Konnect Resource Provisioning

FR7: An operator can provision Konnect teams from declarative YAML files committed to the repository.
FR8: An operator can provision Konnect system accounts and persist their tokens to the configured secrets backend (HashiCorp Vault per ADR #001).
FR9: An operator can provision Konnect control planes referenced by the team YAML resources.
FR10: The provisioning pipeline validates every YAML resource definition against its schema before any infrastructure mutation is attempted.
FR11: The provisioning pipeline rejects YAML resources that declare entitlements outside the documented supported set.
FR12: An operator can re-run the provisioning pipeline idempotently — already-provisioned resources produce no diff and no infrastructure mutation.

#### Dataplane Deployment

FR13: An operator can deploy a Kong Gateway dataplane to a local Kubernetes cluster (OrbStack or Docker Desktop) via the `deploy-dp` Action.
FR14: An operator can deploy a Kong Gateway dataplane to a cloud Kubernetes cluster via the same `deploy-dp` Action by changing only configuration inputs — no source code changes.
FR15: An operator can specify the Kong Gateway image tag and the Helm chart version per `deploy-dp` invocation, with documented defaults.
FR16: A deployed dataplane registers with the hosted Konnect control plane and reports a healthy status in Konnect's view of the dataplane.

#### API Configuration Publishing

FR17: An API-team workflow can lint an OpenAPI specification using the bundled Spectral OWASP ruleset and surface lint failures as PR-time GitHub check feedback.
FR18: An API-team workflow can publish a linted OpenAPI specification to a Konnect-managed dev portal via decK in a single Action invocation.
FR19: Re-running the publish workflow against an unchanged OpenAPI specification produces no observable change in Konnect (idempotent sync).
FR20: Lint failures from the publishing pipeline include file, line, and rule context in the surfaced error — not raw log output.

#### Developer Portal & Dashboards

FR21: An operator can apply Konnect developer-portal configuration (`konnect/developer-portal/config.yaml`, `portal/*.yaml`) declaratively via the `developer-portal` workflow.
FR22: An operator can apply Konnect dashboard configurations (`konnect/dashboards/`) declaratively, with pre-mutation validation.

#### Operator Onboarding Webapp

FR23: An operator can use the bundled Flask webapp (`webapp/onboard_team_app.py`) to author or edit a team YAML resource interactively, producing output that conforms to the YAML schema enforced by FR10.

#### Action Contract Stability

FR24: Every published Composite Action declares all inputs (with `description`, `required`, and `default` for optional inputs) and all outputs (with `description`) in its `action.yml`.
FR25: Every published Composite Action ships a `README.md` documenting its inputs, outputs, side effects, an example caller workflow, and common failure modes — matching the structure of the `provision-konnect-resources` README.
FR27: Breaking changes to any published Composite Action's input or output contract are documented in `MIGRATION.md` with a remediation step for callers.
FR28: A reader can determine the full input/output contract of every published Composite Action by reading the repository alone, without running any workflow.

_Out of MVP scope:_
- ~~FR26~~ — Pin-to-tag stable contract behavior. Deferred to Growth phase per Architecture D4; MVP uses `@main`. Not generating stories.

#### Backend & Target Configuration

FR29: An operator can select the Terraform state backend between local MinIO (default) and AWS S3 (alternative) via documented configuration, without modifying HCL source.
FR30: An operator can select the secrets backend between Konnect Vault and HashiCorp Vault via documented configuration. *(Reframed by Architecture ADR #001: HashiCorp Vault is retained as the sole secrets backend; "selection" collapses to a `VAULT_ADDR` env-var swap pointing at the local docker-compose Vault for the default path or a real Vault cluster for production.)*
FR31: An operator can select the Kubernetes deployment target between local clusters (OrbStack / Docker Desktop, default) and any cloud cluster (alternative) via the `deploy-dp` Action's documented inputs.

#### Migration & Documentation

FR32: The repository provides a `MIGRATION.md` documenting the migration path from the previous AWS-S3-and-HashiCorp-Vault setup to the new local-first defaults, including instructions for users who wish to retain a cloud-backed configuration.
FR33: `MIGRATION.md` documents the Terraform state migration steps required when upgrading the Konnect provider from `3.1.0` to `3.15`, including any required `terraform state mv` operations and verification steps.
FR34: The top-level `README.md` provides a quickstart that takes an SE from a fresh `git clone` to a successfully deployed dataplane, expressed as a sequential list of commands and expected outputs.

### NonFunctional Requirements

#### Performance

NFR1: `make prepare` (cold clone → local execution stack ready) completes within 20 minutes on a clean Apple Silicon MacBook with a typical home internet connection (≥ 50 Mbps).
NFR2: `act`-driven execution of a typical platform workflow (e.g., `onboard-konnect-teams` against a single team, `deploy-dp` against a single dataplane) completes end-to-end within 5 minutes from invocation.
NFR3: The idle local Docker stack (MinIO + GitHub Actions runner + helper services) consumes ≤ 4 GB RAM and ≤ 4 vCPU on a 16 GB MacBook.

#### Security

NFR4: Secrets (`KONNECT_TOKEN`, system-account tokens, AWS keys, Vault tokens) are never emitted to workflow logs by any code path in this repository.
NFR5: All local secret artifacts (`act.secrets`, `.tls/`, `.tmp/`, vendor-specific credential files) are gitignored and excluded from container images. The `make clean` target removes them.
NFR6: Secret material is supplied to Composite Actions via explicit inputs declared in the caller workflow; `secrets: inherit` is not used. Within an Action, secret material flows through `$GITHUB_ENV` only when downstream steps require env-style access.
NFR7: The repository contains no real customer data, real customer names, real internal Kong URLs, or partner identifiers. All example resources reference the fictional `flight-operations` tenant or equivalent fictitious entities.
NFR8: Third-party tooling versions used in the integration surface are exact-pinned where their schema is unstable: `kong/konnect = 3.15`, `decK v1.51.0`, `@stoplight/spectral-owasp-ruleset@^2.0`. Pin updates are explicit, reviewed changes — never "latest."
NFR9: Konnect system-account tokens flow only through the configured secrets backend. They are never exposed as Terraform outputs and never written to disk outside the secrets backend's storage.

#### Reliability & Compatibility

NFR10: 100% of platform workflows (`onboard-konnect-teams`, `developer-portal`, `deploy-dp`, `test-sync-api-configuration`, `publish-api-configuration`) run end-to-end via `act` on macOS without manual hand-edits.
NFR11: The repository is verified to work on the latest two major macOS versions running on Apple Silicon. Intel Macs and Linux are not a tested support matrix.
NFR12: Validation gates (YAML schema validation, Spectral OpenAPI lint, `terraform plan` consistency, schema-required field checks) cannot be bypassed via `continue-on-error: true`, `|| true`, or any equivalent pattern.
NFR13: Error output from any validation, lint, or plan step includes sufficient context (file path, line number, rule ID or resource address) for an SE to identify the cause and apply a documented one-line fix.

#### Scalability

NFR14: The local execution stack is sized for a single Solutions Engineer running a typical demo (one team, one dataplane, one OpenAPI specification). Multi-team scenarios are Vision-scope.

#### Integration & Extensibility

NFR15: Pluggable backend swaps (Terraform state: MinIO ↔ AWS S3; secrets: Konnect Vault ↔ HashiCorp Vault per ADR #001 reframing; Kubernetes target: local ↔ cloud) are achievable by configuration changes alone — no source-code modifications, no Terraform module rewrites, no Action input renames.
NFR17: The Konnect Terraform provider pin is exact (`= 3.15`); provider drift is detectable by `terraform init -upgrade` diff output.

_Out of MVP scope:_
- ~~NFR16~~ — Action contract stability across tagged releases. Deferred to Growth phase alongside FR26; MVP uses `@main`. Not generating stories.

#### Documentation Quality

NFR18: Every published Composite Action's README is non-divergent from its `action.yml` at every release; drift is treated as a release-blocking defect (mechanically enforced by `lint-action-contracts.yaml`).
NFR19: The top-level `README.md` is readable cold (no prior context) in under 30 minutes by a reader unfamiliar with the repository, conveying: (a) the federated platform-ops model and the seam between this repo and API-team repos, (b) the local-first quickstart, (c) the location of the companion API-team reference repository.

### Additional Requirements

Extracted from `architecture.md` — technical decisions and infrastructure scaffolding required for implementation:

- **AR1 (D1, P1):** State backend selection implemented via two committed `.tfbackend` files (`config.minio.tfbackend` for local default, `config.s3.tfbackend` for AWS), selected by `TF_BACKEND_CONFIG` env var. Init invocation: `terraform init -reconfigure -backend-config="$TF_BACKEND_CONFIG"`. Applied identically to **both** Terraform trees: `terraform/konnect-teams/` and `.github/actions/provision-konnect-resources/terraform/`.
- **AR2 (D1):** New shared Composite Action `.github/actions/init-terraform/` introduced. Encapsulates backend selection + provider init for reuse across workflows. Ships with `action.yml` and a P4-conformant `README.md`.
- **AR3 (D1):** Rename `scripts/create-s3-bucket.sh` → `scripts/create-state-bucket.sh`; supports both MinIO and AWS code paths from the same script.
- **AR4 (D2, P2):** `deploy-dp/action.yml` adds two paired inputs — `kubeconfig-path` (default `~/.kube/config`) and `kubeconfig-content` (optional, secret). `kubeconfig-content` wins when both are set; written to `${RUNNER_TEMP}/kubeconfig`. Pattern P2 generalizes the path/content suffix convention for future actions.
- **AR5 (D3, P6):** Konnect Terraform provider migration `3.1.0 → 3.15` is a single-PR scoped change covering `konnect_team`, `konnect_team_role`, `konnect_control_plane`, system-account / vault module resources. Schema diffs against the local provider source at `/Users/jordi.fernandez/github/terraform-provider-konnect`. Both Terraform trees migrate.
- **AR6 (D3, P6):** New `migrations/` directories in both Terraform trees, with the first script `001-konnect-3-15-rename.sh`. Scripts: `set -euo pipefail`, idempotent (every `terraform state mv`/`rm`/`import` guarded by `terraform state list | grep`), header block stating purpose / source/target provider versions / prerequisites.
- **AR7 (D3, P6):** New `make migrate-state` target invokes unapplied migrations in order across both Terraform trees (outer → inner). Applied marker file at `.terraform/migrations-applied` (gitignored).
- **AR8 (D3):** Verification gate — `terraform plan` against a fresh local MinIO backend shows zero diffs after migration.
- **AR9 (D4, NFR18):** New CI workflow `.github/workflows/lint-action-contracts.yaml` mechanically diffs each `action.yml`'s `inputs:` / `outputs:` against the corresponding README's tables. Failure blocks merge.
- **AR10 (D4, P4):** Every published Composite Action's `README.md` follows the canonical H2 section order: Overview → Inputs → Outputs → Side Effects → Example Usage → Failure Modes. New READMEs needed for `deploy-dp`, `publish-api-configuration`, `setup-k8s-tools`, `init-terraform`. Existing `provision-konnect-resources` README updated to P4 structure.
- **AR11 (D5, NFR12, P3):** New CI workflow `.github/workflows/lint-no-bypass.yaml` flags `continue-on-error: true` or `|| true` adjacent to step names matching `^(Validate|Lint|Plan)\b`.
- **AR12 (P3):** Audit pass to ensure every existing validation/lint/plan step in workflows and actions uses the `Validate|Lint|Plan` step-name prefix; rename non-conforming steps before `lint-no-bypass.yaml` ships (or grandfather list).
- **AR13 (D6):** Observability vendor removal — `git grep -i 'datadog\|dynatrace'` enumerates the removal scope; strip from `k8s/values.yaml`, Helm overlays, action inputs/READMEs, top-level docs. Vendor-neutral observability scaffolding (Kong status endpoints, default log format, default Prometheus metrics exposition) is preserved.
- **AR14 (D7, P5):** Single `MIGRATION.md` at repo root with two top-level sections: §1 Legacy cloud-only → local-first; §2 Konnect provider 3.1.0 → 3.15. Per-action breaking changes (FR27) inline as subsections under the relevant migration. Each entry follows the P5 format (Affected / Before / After / Remediation).
- **AR15 (ADR #001):** HashiCorp Vault is retained as the secrets backend in **both** modes. Local default = docker-compose Vault dev container at `http://localhost:8300`, root token from `act.secrets`; production = real Vault cluster, operator-supplied `VAULT_ADDR` + `VAULT_TOKEN`. Same paths, same Terraform module (`terraform/konnect-teams/modules/vault`), same provider — only connection target changes. Konnect Config Store is **out of scope** for this PRD.
- **AR16:** `act.secrets.example` template added at repo root to document the only required operator-supplied values (`KONNECT_TOKEN`, `VAULT_TOKEN=root` for local, `GITHUB_ORG`); `act.secrets` itself stays gitignored.
- **AR17:** Implementation sequence (independently-shippable PRs, per architecture D-impact analysis): (1) Konnect provider 3.15 migration → (2) state backend abstraction + `init-terraform` action → (3) k8s target abstraction → (4) observability removal → (5) docs refresh + contract/bypass lints.

_Note:_ AR12 (P3 step-name audit) will be folded into the bypass-lint story as an acceptance criterion rather than a standalone item. `WHAT_TO_CHANGE.md` is a temporary refactor scratchpad and is intentionally not tracked as a story-generating requirement.

### UX Design Requirements

_Not applicable — `kw-platform-ops` has no UX Design Specification. The repository has no significant UI surface; the Flask onboarding webapp is intentionally a thin operator UI with logic in Bash/Terraform per project-context.md._

### FR Coverage Map

| FR | Epic | Description |
|---|---|---|
| FR1 | Epic 2 | `make prepare` end-to-end on a clean macOS clone |
| FR2 | Epic 2 | MinIO as S3-compatible local Terraform state backend |
| FR3 | Epic 2 | `act`-runnable Actions runner environment |
| FR4 | Epic 2 | Dependency self-discovery with actionable errors (`scripts/check-deps.sh`) |
| FR5 | Epic 2 | Make targets to start / stop / reset the local stack |
| FR6 | Epic 2 | Single-credential bootstrap via gitignored `act.secrets` |
| FR7 | Epic 1 | Konnect teams from declarative YAML (verified post-provider-migration) |
| FR8 | Epic 1 | System accounts persisted to HashiCorp Vault per ADR #001 |
| FR9 | Epic 1 | Konnect control planes provisioned from team YAML |
| FR10 | Epic 1 | YAML schema validation gate before any infrastructure mutation |
| FR11 | Epic 1 | Entitlements rejected when outside the supported set |
| FR12 | Epic 1 | Idempotent provisioning re-runs (no diff, no mutation) |
| FR13 | Epic 3 | Dataplane deploy to local Kubernetes (OrbStack / Docker Desktop) |
| FR14 | Epic 3 | Dataplane deploy to cloud Kubernetes via the same Action |
| FR15 | Epic 3 | `kong-image-tag` and `helm-chart-version` configurable per invocation |
| FR16 | Epic 3 | Deployed dataplane registers and reports healthy in Konnect |
| FR17 | Epic 4 | Spectral OWASP lint with PR-check feedback |
| FR18 | Epic 4 | decK-driven publish to Konnect dev portal |
| FR19 | Epic 4 | Idempotent re-publish against unchanged spec |
| FR20 | Epic 4 | Lint failures include file/line/rule context |
| FR21 | Epic 1 | Developer-portal configuration applied declaratively (Terraform-driven) |
| FR22 | Epic 1 | Dashboard configuration applied with pre-mutation validation |
| FR23 | Epic 5 | Flask onboarding webapp documented in top-level README |
| FR24 | Epic 4 | Every Composite Action declares inputs/outputs in `action.yml` |
| FR25 | Epic 4 | Per-action `README.md` parity (P4 structure) |
| ~~FR26~~ | — | _Out of MVP scope (Growth phase per Architecture D4)_ |
| FR27 | Epic 4 | Breaking changes to action contracts documented in `MIGRATION.md` |
| FR28 | Epic 4 | Action contracts readable from repo without running anything |
| FR29 | Epic 2 | State backend selection via `TF_BACKEND_CONFIG` (MinIO ↔ S3) |
| FR30 | Epic 2 | Secrets backend selection via `VAULT_ADDR` swap (per ADR #001) |
| FR31 | Epic 3 | K8s target selection via `kubeconfig-path` / `kubeconfig-content` |
| FR32 | Epic 5 | `MIGRATION.md` §1 (legacy cloud-only → local-first) |
| FR33 | Epic 1 | `MIGRATION.md` §2 (Konnect provider 3.1.0 → 3.15) |
| FR34 | Epic 5 | Top-level `README.md` local-first quickstart |

## Epic List

### Epic 1: Konnect Provider Modernization (3.1.0 → 3.15)

Goal: Bump the Konnect Terraform provider to `3.15` across **both** Terraform trees (`terraform/konnect-teams/` and `.github/actions/provision-konnect-resources/terraform/`) with idempotent state-migration scripts and a clean-plan verification gate, preserving every existing Konnect-driven capability — team provisioning, system accounts (HashiCorp Vault per ADR #001), control planes, developer portal, dashboards. Ships `MIGRATION.md` §2.
**FRs covered:** FR7, FR8, FR9, FR10, FR11, FR12, FR21, FR22, FR33
**NFRs touched:** NFR8 (exact pin), NFR17 (provider drift detection)
**Additional Requirements:** AR5, AR6, AR7, AR8

### Epic 2: Local-First Demo Bootstrap (Clone-to-First-Team in < 20 min)

Goal: Enable a Solutions Engineer to clone a fresh repo on a clean macOS machine, run `make prepare` with only a `KONNECT_TOKEN` supplied, and within 20 minutes have a runnable local stack capable of provisioning a Konnect team end-to-end via `act` — with no cloud accounts, no external Vault, no kubeconfig handoff. Delivers MinIO as the default state backend, the new shared `init-terraform` composite action, the `create-state-bucket.sh` rename, and the `act.secrets.example` template.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR29, FR30
**NFRs touched:** NFR1 (< 20 min cold setup), NFR3 (idle resource budget), NFR15 (config-only swap pattern emerges here)
**Additional Requirements:** AR1, AR2, AR3, AR15, AR16

### Epic 3: Pluggable Kubernetes Target for Dataplane Deploys

Goal: Enable an operator to deploy a Kong Gateway dataplane to either a local Kubernetes cluster (OrbStack / Docker Desktop, default) or any cloud cluster (EKS / GKE / AKS) using the same `deploy-dp` Action — by passing only configuration inputs (`kubeconfig-path` / `kubeconfig-content`). Completes Journey 1 (local demo) and unlocks Journey 2 (mid-demo cloud swap). Non-breaking additive change.
**FRs covered:** FR13, FR14, FR15, FR16, FR31
**NFRs touched:** NFR15 (config-only k8s target swap)
**Additional Requirements:** AR4

### Epic 4: API Publishing & Action Contract Stability

Goal: Enable an API-team developer to consume the platform's Composite Actions with documented input/output contracts, mechanically-enforced README ↔ `action.yml` non-divergence, mechanically-enforced quality-gate bypass prevention, and PR-time Spectral feedback when an OpenAPI spec breaks lint rules. Delivers per-action README parity (P4 structure) for `deploy-dp`, `publish-api-configuration`, `setup-k8s-tools`, and `init-terraform`; updates `provision-konnect-resources` README to P4 structure; ships the `lint-action-contracts.yaml` and `lint-no-bypass.yaml` CI workflows.
**FRs covered:** FR17, FR18, FR19, FR20, FR24, FR25, FR27, FR28
**NFRs touched:** NFR12 (no bypass — enforced by lint), NFR18 (README ↔ `action.yml` non-divergence — enforced by lint)
**Additional Requirements:** AR9, AR10, AR11, AR12 (P3 step-name audit as AC on the bypass-lint story)

### Epic 5: Documentation Synthesis, Migration Path & Vendor Cleanup

Goal: A reader (Marcus / prospect's platform lead) opens the top-level `README.md` cold and within 30 minutes understands the federated platform-ops model, the local-first quickstart, and the location of the companion API-team repo. SEs and forks can navigate `MIGRATION.md` to retain a cloud-backed configuration when needed. The repository contains zero Datadog / Dynatrace references — vendor-neutral observability scaffolding (Kong status endpoints, default log format, Prometheus metrics) is preserved. Lands the top-level README rewrite, `MIGRATION.md` §1 (synthesizing legacy → local migration covering Epics 2 + 3), the Datadog/Dynatrace strip, and Flask onboarding webapp documentation.
**FRs covered:** FR23, FR32, FR34
**NFRs touched:** NFR7 (no vendor identifiers), NFR19 (README cold-readable in < 30 min)
**Additional Requirements:** AR13, AR14

---

**Sequencing & Dependencies:**

- **Epic 1** lands first — provider migration is the riskiest schema work; subsequent epics verify on a working baseline.
- **Epic 2** lands second — local stack runnability depends on Epic 1's clean plan against MinIO backend.
- **Epic 3** can land any time after Epic 2 — additive, non-breaking change to `deploy-dp`.
- **Epic 4** can land in parallel with Epic 3 — touches different files (Composite Actions + new CI workflows).
- **Epic 5** lands last — top-level README and `MIGRATION.md` §1 require Epics 2–4's changes to exist for an accurate synthesis.

Each epic delivers complete, standalone value: working modern provider (Epic 1), working local stack (Epic 2), working pluggable k8s (Epic 3), enforced contract stability (Epic 4), navigable docs and clean codebase (Epic 5). No epic requires a future epic to function.

## Epic 1: Konnect Provider Modernization (3.1.0 → 3.15)

Bump `kong/konnect` to `3.15` across both Terraform trees with idempotent state migrations and a clean-plan verification gate, preserving all existing Konnect-driven capabilities.

### Story 1.1: Audit Konnect provider 3.15 schema diffs against current resource usage

As a platform engineer,
I want a documented inventory of every Konnect Terraform resource currently in use and its attribute-level diff against provider 3.15,
So that subsequent migration stories have an explicit, reviewable target rather than blind code changes.

**Acceptance Criteria:**

**Given** the local provider source at `/Users/jordi.fernandez/github/terraform-provider-konnect`
**When** I inventory all `kong/konnect` resources referenced in `terraform/konnect-teams/**/*.tf` and `.github/actions/provision-konnect-resources/terraform/**/*.tf`
**Then** every resource type currently in use is enumerated (e.g., `konnect_team`, `konnect_team_role`, `konnect_control_plane`, system-account / vault module resources, plus every resource type referenced across the ~30 submodules under `provision-konnect-resources/terraform/modules/` — including portal and dashboard modules)

**Given** the inventory is complete
**When** I diff each resource type's attributes between provider 3.1.0 and 3.15 by inspecting the local provider source's CHANGELOG, schemas, and docs
**Then** every required attribute rename, new required attribute, removed attribute, and deprecated attribute is documented per resource type
**And** every resource that requires a `terraform state mv` operation is explicitly listed with source and target form

### Story 1.2: Bump Konnect provider to 3.15 and apply schema updates in `terraform/konnect-teams/`

As a platform engineer,
I want the platform-team Terraform tree running on `kong/konnect = 3.15` with all required attribute changes applied,
So that platform-team resources (teams, system accounts, control planes, vault rooting) plan cleanly against the modern provider.

**Acceptance Criteria:**

**Given** the current `terraform/konnect-teams/providers.tf` pinning `kong/konnect = 3.1.0`
**When** I update the pin to `kong/konnect = 3.15` (exact, not `~>`)
**Then** `terraform init -upgrade` in `terraform/konnect-teams/` succeeds with the new provider downloaded

**Given** the schema diffs from Story 1.1
**When** I update every `.tf` file in `terraform/konnect-teams/` that references a changed attribute (resource declarations, module inputs, locals, outputs)
**Then** `terraform validate` passes with no schema errors in the root module and every submodule under `modules/`
**And** `terraform plan` against the existing state produces only the diffs predicted by the schema-change inventory — no surprise diffs

### Story 1.3: Bump Konnect provider to 3.15 and apply schema updates in `.github/actions/provision-konnect-resources/terraform/`

As a platform engineer,
I want the API-team-facing Terraform tree running on `kong/konnect = 3.15` with all required attribute changes applied across the ~30 submodules (including portal_* and dashboard_* submodules),
So that API teams calling `provision-konnect-resources` get a working modern-provider implementation behind the action, with developer-portal and dashboard provisioning preserved.

**Acceptance Criteria:**

**Given** the current `.github/actions/provision-konnect-resources/terraform/providers.tf` pinning `kong/konnect = 3.1.0`
**When** I update the pin to `kong/konnect = 3.15`
**Then** `terraform init -upgrade` in this tree succeeds

**Given** the schema diffs from Story 1.1
**When** I update every `.tf` file under `.github/actions/provision-konnect-resources/terraform/` (root + all submodules under `modules/`, including portal_* and dashboard_* submodules) that references a changed attribute
**Then** `terraform validate` passes with no schema errors in the root module and every submodule
**And** `terraform plan` against the representative test fixtures (e.g., `test/provisioning/fixtures/`) produces only the diffs predicted by the schema-change inventory

### Story 1.4: Implement idempotent `001-konnect-3-15-rename.sh` state-migration scripts in both Terraform trees

As a platform engineer,
I want re-runnable state-migration scripts that perform every `terraform state mv` / `state rm` / `import` operation required by the provider upgrade,
So that operators with existing state can upgrade in place without resource destruction and the script can be safely re-executed without harm.

**Acceptance Criteria:**

**Given** Architecture pattern P6 (state-migration script convention)
**When** I create `terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh` and `.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`
**Then** each script begins with `set -euo pipefail` and a header comment block stating purpose, source provider version (`3.1.0`), target provider version (`3.15`), prerequisites, and an idempotency note

**Given** the renames identified in Story 1.1
**When** the script executes against pre-migration state
**Then** every `terraform state mv` / `state rm` / `import` operation is guarded by a `terraform state list | grep` precondition check
**And** every state operation completes without error

**Given** the script has already been run successfully
**When** I run the same script a second time on the now-migrated state
**Then** the script produces zero state operations and exits 0 (idempotent)

**Given** the script has run successfully
**When** I run `terraform plan` afterwards in the affected tree
**Then** the plan shows zero diffs for every resource the script touched

### Story 1.5: Add `make migrate-state` driver with applied-marker file

As a platform engineer,
I want a single Make target that runs unapplied migration scripts in both Terraform trees in the correct order,
So that operators don't need to track which migrations have been applied or in which sequence.

**Acceptance Criteria:**

**Given** the migration scripts from Story 1.4 exist in both Terraform trees
**When** I run `make migrate-state` from a fresh checkout (no applied-marker files present)
**Then** `terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh` runs first (outer tree)
**And** `.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh` runs second (inner tree)
**And** on success, each tree's `.terraform/migrations-applied` file is updated to record which scripts have completed

**Given** all migrations have already been applied
**When** I run `make migrate-state` again
**Then** no migration scripts execute and the target exits 0 with a clear message indicating no migrations are pending

**Given** the applied-marker convention
**When** I inspect `.gitignore`
**Then** `.terraform/migrations-applied` is gitignored across both Terraform trees

### Story 1.6: Verify clean plan against fresh local MinIO backend and author `MIGRATION.md` §2

As a platform engineer,
I want the provider upgrade verified end-to-end against a fresh local MinIO state backend, with the migration procedure documented in `MIGRATION.md` §2,
So that the technical-success gate is met (clean plan, zero diffs) and operators forking the repo can execute the same upgrade against their state.

**Acceptance Criteria:**

**Given** the local docker-compose stack is running (MinIO at `:9000`)
**When** I run `terraform init -reconfigure -backend-config=...` in each Terraform tree pointing at MinIO with a fresh state file, then apply the canonical fixtures (e.g., `teams/flight-operations.yaml`)
**And** then run `make migrate-state`
**Then** `terraform plan` afterwards produces zero diffs in both trees

**Given** Architecture pattern P5 (`MIGRATION.md` entry format)
**When** I author `MIGRATION.md` at the repo root with the top-level section "Migration 2 — Konnect provider 3.1.0 → 3.15"
**Then** the section follows the P5 format (Affected / Before / After / Remediation)
**And** documents: the provider pin update (`3.1.0` → `3.15`), the per-resource schema diff summary from Story 1.1, the `make migrate-state` invocation, and the verification procedure
**And** documents a downgrade / rollback path back to `3.1.0` for the case where the migration surfaces an unforeseen issue post-merge

## Epic 2: Local-First Demo Bootstrap (Clone-to-First-Team in < 20 min)

Enable a Solutions Engineer to clone a fresh repo on a clean macOS machine, run `make prepare` with only a `KONNECT_TOKEN` supplied, and within 20 minutes have a runnable local stack provisioning a Konnect team end-to-end via `act` — with no cloud accounts, no external Vault, and no kubeconfig handoff.

### Story 2.1: Add `config.minio.tfbackend` to both Terraform trees alongside existing `config.s3.tfbackend`

As a platform engineer,
I want both Terraform trees to ship with two committed backend-config files — `config.minio.tfbackend` (local default) and `config.s3.tfbackend` (AWS alternative) — selected by a single env var,
So that operators can switch state backends declaratively without editing HCL or templating files.

**Acceptance Criteria:**

**Given** Architecture pattern P1 (backend-config file naming and selection)
**When** I create `terraform/konnect-teams/config.minio.tfbackend` and `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend`
**Then** each file declares the MinIO-specific partial-backend keys (`endpoint`, `force_path_style = true`, `skip_credentials_validation = true`, `skip_metadata_api_check = true`, `skip_requesting_account_id = true`, `region`)
**And** the existing `config.s3.tfbackend` is retained unchanged as the alternative path

**Given** the local docker-compose stack is running (MinIO available at `http://localhost:9000`, bucket `tfstate` auto-created)
**When** I run `terraform init -reconfigure -backend-config=config.minio.tfbackend` in either tree
**Then** init succeeds and reads/writes state against MinIO with no AWS credentials required

**Given** AWS credentials are present in the environment
**When** I run `terraform init -reconfigure -backend-config=config.s3.tfbackend` in either tree
**Then** init succeeds against the configured S3 bucket — with no source-code change between the two invocations

### Story 2.2: Create shared `init-terraform/` Composite Action

As a platform engineer,
I want a single reusable Composite Action that encapsulates Terraform init + backend selection,
So that every workflow performing Terraform operations uses one canonical init implementation, and adding new workflows doesn't duplicate backend-selection plumbing.

**Acceptance Criteria:**

**Given** Architecture decision D1 (state backend abstraction) and pattern P4 (action README structure)
**When** I create `.github/actions/init-terraform/action.yml`
**Then** the action declares inputs `terraform-dir` (required) and `backend-config-path` (optional, default `config.minio.tfbackend`)
**And** the action runs `terraform init -reconfigure -backend-config="${{ inputs.backend-config-path }}"` in the supplied directory using `runs.using: composite`
**And** every step uses `shell: bash` and references the action directory via `${{ github.action_path }}` where applicable

**Given** the action exists
**When** I create `.github/actions/init-terraform/README.md`
**Then** the README follows P4 structure exactly (H2 sections in order: Overview, Inputs, Outputs, Side Effects, Example Usage, Failure Modes)
**And** the Inputs table lists every input from `action.yml` with matching name, required flag, and default
**And** the Example Usage section includes a complete `uses:` block with both a MinIO call and an S3 call

**Given** a caller workflow uses the action
**When** I invoke `uses: ./.github/actions/init-terraform` with `terraform-dir: terraform/konnect-teams` and the default backend-config-path
**Then** Terraform initializes successfully against the local MinIO

### Story 2.3: Rewire platform workflows to use `init-terraform` and `TF_BACKEND_CONFIG`

As a platform engineer,
I want every platform workflow that performs Terraform operations to call the shared `init-terraform` action with `TF_BACKEND_CONFIG` controlling backend selection,
So that backend selection is uniform across the workflow surface and `act`-driven local runs default to MinIO without hand-edits.

**Acceptance Criteria:**

**Given** Stories 2.1 and 2.2 are complete
**When** I update `.github/workflows/onboard-konnect-teams.yaml`, `.github/workflows/developer-portal.yaml`, `.github/workflows/test-sync-api-configuration.yaml`, and any other Terraform-touching workflow
**Then** each workflow invokes `uses: ./.github/actions/init-terraform` instead of running `terraform init` inline
**And** each workflow declares a job-level env var `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` and passes it as the action's `backend-config-path` input
**And** the existing `scripts/create-s3-bucket.sh` invocation is replaced with `scripts/create-state-bucket.sh` (delivered in Story 2.4)

**Given** an SE has the local docker-compose stack running
**When** they execute `act -W .github/workflows/onboard-konnect-teams.yaml` with no env overrides and a valid `KONNECT_TOKEN` in `act.secrets`
**Then** the workflow runs end-to-end against MinIO state and produces a successful `terraform plan` / `apply` against the canonical `flight-operations` team fixture

**Given** an operator wants to target AWS S3 instead
**When** they set `TF_BACKEND_CONFIG=config.s3.tfbackend` and provide AWS credentials
**Then** the same workflow runs end-to-end against AWS S3 with no other change

### Story 2.4: Rename `create-s3-bucket.sh` → `create-state-bucket.sh` with MinIO + AWS support

As a platform engineer,
I want a single bucket-creation script that supports both MinIO (local default) and AWS S3 (alternative),
So that workflows have one canonical bucket-bootstrap code path regardless of the selected backend.

**Acceptance Criteria:**

**Given** the existing `scripts/create-s3-bucket.sh`
**When** I rename it to `scripts/create-state-bucket.sh` and update its logic
**Then** the script accepts a backend type (e.g., via env var or first argument: `minio` | `aws`) with `minio` as the default
**And** for `minio` mode, the script ensures the bucket exists on the local MinIO via the appropriate MinIO client (or `aws s3` with `--endpoint-url` override)
**And** for `aws` mode, the script preserves the original AWS S3 creation behavior with encryption and access-control settings intact
**And** `set -euo pipefail` is preserved at the top of the script

**Given** the rename is complete
**When** I `grep -r 'create-s3-bucket'` across the repo
**Then** every reference (workflows, scripts, READMEs, Makefile) is updated to `create-state-bucket.sh`
**And** the script is executable (`chmod +x`)

**Given** the docker-compose MinIO is running with no `tfstate` bucket
**When** I run `scripts/create-state-bucket.sh tfstate`
**Then** the bucket is created on MinIO and the script exits 0
**And** running it a second time is idempotent (no error on existing bucket)

### Story 2.5: Add `act.secrets.example` template and update prep script

As a Solutions Engineer,
I want a committed `act.secrets.example` template documenting every operator-supplied value with placeholders, plus a prep script that creates `act.secrets` from it on first run,
So that I know exactly which credentials I need to supply on a fresh clone, and `act.secrets` itself stays gitignored.

**Acceptance Criteria:**

**Given** no `act.secrets` file exists in a fresh clone
**When** I create `act.secrets.example` at the repo root
**Then** the file contains `KONNECT_TOKEN=` (with an inline comment pointing at where to obtain a Konnect personal token), `VAULT_TOKEN=root` (with a comment noting this is the docker-compose dev-mode default), and `GITHUB_ORG=` (with a comment explaining its use)
**And** `act.secrets` itself is gitignored (verify by `git check-ignore act.secrets`)

**Given** `scripts/prep-act-secrets.sh` exists
**When** I update the script so that on a fresh clone (no `act.secrets`) it copies `act.secrets.example` to `act.secrets`
**Then** running `make prepare` on a fresh clone produces an `act.secrets` file ready for the operator to fill in
**And** the script emits a clear, terminal-friendly message listing which fields require operator input before workflows can run
**And** if `act.secrets` already exists, the script does not overwrite it

### Story 2.6: End-to-end verification of `make prepare` against MinIO + Vault on a clean macOS clone

As a Solutions Engineer,
I want the full clone-to-first-team-provisioned cycle measured and verified on a clean macOS machine,
So that NFR1 (< 20 min cold setup) and NFR3 (≤ 4 GB / 4 vCPU idle) are met as MVP acceptance gates and Journey 1's promise holds.

**Acceptance Criteria:**

**Given** a clean Apple Silicon macOS machine with Docker installed and a typical home internet connection (≥ 50 Mbps)
**When** I `git clone` the repo, fill in `KONNECT_TOKEN` in `act.secrets`, and run `make prepare`
**Then** the docker-compose stack (MinIO on `:9000`, HashiCorp Vault dev container on `:8300`, helper services) comes up
**And** `scripts/check-deps.sh` either confirms all required dependencies (Docker, `act`, `gh`, `terraform`, `helm`, `kubectl`) are present at compatible versions or produces an actionable error message naming the missing/incompatible tool and how to install it
**And** the entire `make prepare` cycle completes in < 20 minutes wall-clock from a clean clone

**Given** the prepared local stack is idle
**When** I measure resource consumption (e.g., via `docker stats` over a 60-second window)
**Then** total RAM consumed is ≤ 4 GB and total CPU is ≤ 4 vCPU

**Given** the prepared stack
**When** I run `act -W .github/workflows/onboard-konnect-teams.yaml` with the `flight-operations.yaml` team fixture and a valid `KONNECT_TOKEN`
**Then** the workflow completes end-to-end (validate → init → plan → apply) and provisions the team in Konnect, with `KONNECT_TOKEN` and `VAULT_TOKEN` flowing through `act.secrets` only and never appearing in workflow logs (verify NFR4 by `grep`)
**And** the entire workflow completes in ≤ 5 minutes from invocation (NFR2 acceptance gate)

**Given** the prepared stack
**When** I run `make clean` (or `make down` per the existing convention)
**Then** all docker-compose services stop, gitignored artifacts (`.tls/`, `.tmp/`) are removed, and the working tree is clean for a re-prep cycle (FR5)

## Epic 3: Pluggable Kubernetes Target for Dataplane Deploys

Operator deploys a Kong Gateway dataplane to a local Kubernetes cluster (OrbStack / Docker Desktop, default) or any cloud cluster (EKS / GKE / AKS) using the same `deploy-dp` Action by passing only configuration inputs. Non-breaking additive change.

### Story 3.1: Add paired `kubeconfig-path` / `kubeconfig-content` inputs to `deploy-dp` action

As a platform engineer,
I want `deploy-dp/action.yml` to accept the kubeconfig in either path-on-disk form (local CI / operator workstation) or raw-content form (cloud CI without a host kubeconfig),
So that the same action drives deploys to OrbStack, Docker Desktop, EKS, GKE, and AKS by configuration alone.

**Acceptance Criteria:**

**Given** Architecture decision D2 and pattern P2 (paired path/content inputs)
**When** I update `.github/actions/deploy-dp/action.yml`
**Then** the action declares two new inputs: `kubeconfig-path` (optional, default `~/.kube/config`, description references local-cluster use) and `kubeconfig-content` (optional, no default, description marks it as a secret-style input for cloud-CI use)
**And** existing inputs (`kong-image-tag`, `helm-chart-version`, etc.) are unchanged so the action contract remains backwards-compatible (FR15 preserved)

**Given** the action runs
**When** `kubeconfig-content` is set (with or without `kubeconfig-path`)
**Then** the action writes the content to `${RUNNER_TEMP}/kubeconfig` and exports `KUBECONFIG=${RUNNER_TEMP}/kubeconfig` for subsequent steps
**And** the kubeconfig content never appears in workflow logs (verify by `grep` of the captured log output — NFR4 enforcement)

**Given** the action runs
**When** only `kubeconfig-path` is set (or both are unset)
**Then** the action exports `KUBECONFIG=<resolved kubeconfig-path>` (resolving `~` to `$HOME` if present)
**And** no temporary file is written

**Given** `kubeconfig-content` is set
**When** the action completes (success or failure)
**Then** `${RUNNER_TEMP}/kubeconfig` is the only on-disk artifact containing the kubeconfig and is cleaned up by the runner's normal `${RUNNER_TEMP}` lifecycle

**Given** `.github/actions/deploy-dp/README.md` exists
**When** I update its Inputs table to include the two new inputs (matching name, required flag, default — minimal consistency with `action.yml`)
**Then** the Example Usage section shows both forms — a local-default call (no kubeconfig inputs) and a cloud call (`kubeconfig-content: ${{ secrets.CLOUD_KUBECONFIG }}`)

_(Note: full P4-conformant README rewrite for `deploy-dp` lands in Epic 4 alongside the contract lint; this story keeps the README consistent with the new inputs in the meantime.)_

### Story 3.2: Verify local Kubernetes deployment end-to-end (OrbStack / Docker Desktop)

As a Solutions Engineer,
I want the `deploy-dp` action to install a Kong Gateway dataplane to my local Kubernetes cluster (OrbStack or Docker Desktop) with no kubeconfig inputs supplied,
So that Journey 1's clone-to-first-dataplane promise holds end-to-end.

**Acceptance Criteria:**

**Given** the local docker-compose stack is running, the local Kubernetes cluster (OrbStack or Docker Desktop) is the active kubeconfig context, and `KONNECT_TOKEN` is set in `act.secrets`
**When** I invoke `act -W .github/workflows/deploy-dp.yaml` with the default `helm-chart-version` (`2.45.0`) and default `kong-image-tag` (`3.11.0.2`) and no kubeconfig inputs
**Then** the action installs the `kong/kong` Helm chart to the local cluster
**And** the deployed dataplane pod reaches `Ready` status within the workflow's wait period
**And** the dataplane registers with the hosted Konnect control plane and is visible as a healthy dataplane in Konnect's UI/API (FR16)

**Given** the same scenario
**When** I override `kong-image-tag` and `helm-chart-version` per invocation
**Then** Helm installs the requested chart version with the requested image tag (FR15 preserved)

**Given** the clustering endpoint URL handling already documented in project-context.md
**When** the action passes the Konnect cluster control-plane endpoint to Helm
**Then** the `https://` prefix is stripped before being passed to `--set env.cluster_control_plane=...:443` (existing behavior preserved; verified)

**Given** the workflow completes
**When** I inspect the workflow logs
**Then** no Konnect or Vault secrets appear in the captured output (NFR4)
**And** the workflow completed in ≤ 5 minutes (NFR2)

### Story 3.3: Verify cloud Kubernetes deployment via `kubeconfig-content`

As a platform engineer,
I want the same `deploy-dp` action to install a dataplane to a cloud Kubernetes cluster (EKS / GKE / AKS) by passing the cloud kubeconfig as a secret-style input,
So that Journey 2's "can this run on EKS instead?" mid-demo swap is delivered with no source-code change.

**Acceptance Criteria:**

**Given** access to any cloud Kubernetes cluster (EKS, GKE, AKS, or equivalent) for which the engineer has a working kubeconfig
**When** I run a workflow that calls `deploy-dp` and passes the cloud kubeconfig YAML via `kubeconfig-content: ${{ secrets.CLOUD_KUBECONFIG }}`
**Then** the action installs the `kong/kong` chart on the cloud cluster
**And** the dataplane registers with the hosted Konnect control plane and reports healthy in Konnect (FR16)

**Given** the same workflow
**When** I inspect the workflow logs
**Then** no portion of the cloud kubeconfig content appears in the logs — including server URL, cluster name, user-token fragments, or certificate data (NFR4 verification)
**And** `${RUNNER_TEMP}/kubeconfig` is the only on-disk location the kubeconfig is written to during the run

**Given** the action contract
**When** I diff the action's behavior between the local-default invocation (Story 3.2) and the cloud invocation (this story)
**Then** the only difference is the kubeconfig source — every other input, output, and side effect is identical (FR14, FR31, NFR15)

## Epic 4: API Publishing & Action Contract Stability

API-team developer consumes the Composite Actions with documented inputs, mechanically-enforced README ↔ `action.yml` non-divergence, mechanically-enforced quality-gate bypass prevention, and PR-time Spectral feedback when an OpenAPI spec breaks lint rules.

### Story 4.1: Audit and complete `action.yml` declarations for every published Composite Action

As a platform engineer,
I want every published Composite Action's `action.yml` to declare all inputs (with `description`, `required`, and `default` for optional inputs) and all outputs (with `description`),
So that the contract is fully visible from the action definition alone — satisfying FR24 and giving the contract lint (Story 4.3) something to diff against.

**Acceptance Criteria:**

**Given** the published Composite Actions: `deploy-dp`, `provision-konnect-resources`, `publish-api-configuration`, `setup-k8s-tools`, and `init-terraform` (from Epic 2)
**When** I audit each `action.yml`
**Then** every input declares `description` (non-empty, descriptive, not just the input name) and `required` (true | false)
**And** every optional input (`required: false`) declares a `default` value
**And** every output declares `description`
**And** every input name is kebab-case (per project-context.md naming rules)

**Given** any gaps surface during the audit
**When** I patch the affected `action.yml` files
**Then** the audit re-runs cleanly with zero gaps, and the patched files preserve all existing input/output names (no breaking renames in this story)

### Story 4.2: Author P4-conformant README for every published Composite Action

As an API-team developer,
I want each published Composite Action to ship a `README.md` documenting its purpose, inputs, outputs, side effects, example caller, and failure modes — with structure consistent across actions,
So that I can determine the contract of any action by reading the repo, without running anything (FR28), and onboarding to a new action takes minutes.

**Acceptance Criteria:**

**Given** Architecture pattern P4 (action README structure) and the existing canonical example at `.github/actions/provision-konnect-resources/README.md`
**When** I create or update each of `.github/actions/deploy-dp/README.md`, `.github/actions/publish-api-configuration/README.md`, `.github/actions/setup-k8s-tools/README.md`, and update `.github/actions/provision-konnect-resources/README.md` for any drift
**Then** every README has H2 sections in this exact order: `## Overview`, `## Inputs`, `## Outputs`, `## Side Effects`, `## Example Usage`, `## Failure Modes`
**And** the `## Inputs` table has columns `Name | Description | Required | Default` and lists every entry from the action's `action.yml` `inputs:` block with matching values
**And** the `## Outputs` table has columns `Name | Description` and lists every entry from the action's `outputs:` block
**And** the `## Example Usage` section provides a complete, copy-pasteable `uses:` block with realistic input values (no placeholders like `<TODO>`)
**And** the `## Side Effects` section enumerates what the action mutates (Konnect resources, Vault paths, Kubernetes resources, files written) per FR25

**Given** `.github/actions/init-terraform/README.md` was already written to P4 structure in Epic 2 Story 2.2
**When** I re-verify it against this story's structural rules
**Then** it passes unchanged (or is patched to bring it into alignment if any drift is found)

### Story 4.3: Implement `lint-action-contracts.yaml` CI workflow enforcing README ↔ `action.yml` non-divergence

As a platform engineer,
I want a CI workflow that mechanically diffs each `action.yml`'s declared `inputs:` / `outputs:` against the corresponding README's Inputs / Outputs tables and blocks merge on drift,
So that NFR18 is enforced automatically and contract drift becomes a release-blocking defect rather than a manual review concern.

**Acceptance Criteria:**

**Given** Architecture decision D4 and the per-action READMEs from Story 4.2
**When** I create `.github/workflows/lint-action-contracts.yaml`
**Then** the workflow triggers on `pull_request` events and on `push` to `main`
**And** the workflow's lint step uses a small `yq | python` (or equivalent) script located at `.github/workflows/scripts/lint-action-contracts.py` (or inline) that, for each `.github/actions/<name>/action.yml`:
  1. Parses `inputs:` and `outputs:` from `action.yml`
  2. Parses the corresponding README's Inputs and Outputs tables
  3. Reports any difference in input/output names, required flags, or default values
**And** the lint step's `name:` begins with `Lint` (per Pattern P3) so it is covered by the bypass detector from Story 4.4

**Given** an action.yml is changed without updating its README (or vice versa)
**When** the workflow runs
**Then** the workflow fails with a message naming the specific input/output that drifted, in which file, with the source-of-truth and divergent values shown
**And** the failure message reminds the contributor that breaking input/output changes require an entry in `MIGRATION.md` (FR27)

**Given** all action.yml/README pairs are in sync (after Stories 4.1 and 4.2 land)
**When** the workflow runs on the default branch
**Then** the workflow succeeds with a clean exit

### Story 4.4: Implement `lint-no-bypass.yaml` CI workflow with P3 step-name audit

As a platform engineer,
I want a CI workflow that detects validation, lint, or plan steps that have been silently bypassed via `continue-on-error: true` or `|| true` patterns, with all existing gate steps renamed to conform to the P3 step-name prefix as a prerequisite,
So that NFR12 is mechanically enforced and a developer cannot quietly disable a quality gate.

**Acceptance Criteria:**

**Given** Architecture decision D5 and pattern P3 (step-name prefix `^(Validate|Lint|Plan)\b`)
**When** I audit every step in `.github/workflows/*.yaml` and `.github/actions/*/action.yml` (and `action.yaml`)
**Then** every step performing a validation, lint, or plan operation has a `name:` whose leading word is one of `Validate`, `Lint`, or `Plan`
**And** any non-conforming gate step is renamed (e.g., `Spectral OpenAPI check` → `Lint OpenAPI with Spectral`; `terraform plan` → `Plan Terraform changes`)

**Given** the audit is complete
**When** I create `.github/workflows/lint-no-bypass.yaml`
**Then** the workflow triggers on `pull_request` and `push` to `main`
**And** the workflow's lint step parses every `.github/workflows/*.yaml` and `.github/actions/*/action.{yml,yaml}` file and flags any step whose `name:` matches `^(Validate|Lint|Plan)\b` AND has either `continue-on-error: true` or contains `|| true` inside its `run:` block

**Given** a contributor adds `continue-on-error: true` to a step named `Plan Terraform changes`
**When** the workflow runs on their PR
**Then** the workflow fails with a message naming the offending file, step, and the bypass pattern detected

**Given** all gate steps conform and no bypass patterns exist
**When** the workflow runs on `main`
**Then** the workflow succeeds

### Story 4.5: Verify API publishing pipeline (Spectral lint + decK sync) end-to-end

As an API-team developer,
I want the `publish-api-configuration` action to lint my OpenAPI spec with the OWASP ruleset, surface failures clearly in PR checks, and idempotently sync the spec to the Konnect dev portal via decK,
So that FR17–FR20 are verified to still work post-refactor and Journey 4 (Priya's invisible-platform-team experience) holds.

**Acceptance Criteria:**

**Given** the local stack is running and the action's bundled Spectral OWASP ruleset (`@stoplight/spectral-owasp-ruleset@^2.0`) is intact
**When** I run a workflow that calls `publish-api-configuration` with a deliberately malformed OpenAPI spec (e.g., missing `info.x-business-unit` or violating an OWASP rule)
**Then** the Spectral lint step fails the workflow
**And** the failure output includes file path, line number, and rule ID for each violation (FR20, NFR13)
**And** the failure surfaces in the PR check summary in a form that GitHub displays prominently (FR17)
**And** the decK sync step does not run (NFR12 — gates cannot be bypassed)

**Given** a well-formed OpenAPI spec
**When** I run the same workflow
**Then** Spectral lint passes
**And** decK syncs the spec to the configured Konnect dev portal (FR18)
**And** the dev portal reflects the published API

**Given** the spec is unchanged from the previous successful run
**When** I re-run the workflow
**Then** decK reports no changes and exits 0 — no observable mutation in Konnect (FR19, idempotent sync)

**Given** the workflow runs to completion
**When** I inspect the captured logs
**Then** `KONNECT_TOKEN` and any other secret material does not appear in the output (NFR4)
**And** the workflow completes in ≤ 5 minutes (NFR2)

## Epic 5: Documentation Synthesis, Migration Path & Vendor Cleanup

Reader opens the top-level `README.md` cold and within 30 minutes understands the federated platform-ops model, the local-first quickstart, and the companion-repo location. SEs and forks can navigate `MIGRATION.md` to retain a cloud-backed configuration. The repository contains zero Datadog / Dynatrace references; vendor-neutral observability scaffolding is preserved.

### Story 5.1: Strip Datadog and Dynatrace references repository-wide

As a platform engineer,
I want every Datadog and Dynatrace reference removed from the repository while vendor-neutral observability scaffolding (Kong status endpoints, default log format, Prometheus metrics) is preserved,
So that NFR7's "no partner identifiers" intent and the PRD MVP §5 vendor-removal item are satisfied without losing demo-relevant generic telemetry.

**Acceptance Criteria:**

**Given** Architecture decision D6 and the enumeration approach (`git grep -i 'datadog\|dynatrace\|dd-\|dt-'`)
**When** I run the grep across all tracked files
**Then** I produce a complete inventory of references across `k8s/values.yaml`, any chart overlays in `.github/actions/deploy-dp/k8s/`, action inputs and READMEs, top-level documentation, and any helper scripts

**Given** the inventory is complete
**When** I remove references from `k8s/values.yaml` and any other tracked files (action inputs, README snippets, sample configs)
**Then** post-strip, `git grep -i 'datadog\|dynatrace'` returns zero matches in tracked files
**And** vendor-neutral observability scaffolding (Kong status endpoints, default log format, default Prometheus metrics exposition) remains intact and unchanged

**Given** the strip is complete
**When** I run the Epic 3 verification of `deploy-dp` against the local Kubernetes cluster
**Then** the dataplane still deploys, registers with Konnect, and reports healthy — no observability-removal regression on the deploy path

**Given** legacy users may rely on the removed observability stanzas
**When** I update `MIGRATION.md` §1 in Story 5.2
**Then** the migration entry includes a "Datadog and Dynatrace references removed" subsection pointing legacy users to integrate observability via a separate repository (per PRD out-of-scope statement)

### Story 5.2: Author `MIGRATION.md` §1 (Legacy cloud-only → local-first) synthesizing Epics 2–4

As an operator forking this repo from a pre-refactor version,
I want `MIGRATION.md` §1 to describe every change between the legacy AWS-S3 + HashiCorp-Vault + cloud-K8s default and the new local-first defaults, with explicit instructions for retaining a cloud-backed configuration,
So that I can choose between adopting the local defaults or keeping my existing cloud-backed setup with no surprises.

**Acceptance Criteria:**

**Given** Architecture pattern P5 (`MIGRATION.md` entry format) and the existing `MIGRATION.md` already containing §2 from Epic 1
**When** I author "Migration 1 — Legacy cloud-only → local-first" as the first top-level section in `MIGRATION.md`
**Then** the section covers each of these subsections, each following P5 format (Affected / Before / After / Remediation):
  1. **State backend default** — AWS S3 → MinIO; how to set `TF_BACKEND_CONFIG=config.s3.tfbackend` to retain S3
  2. **Secrets backend connection** — `VAULT_ADDR` swap from a real Vault cluster to docker-compose Vault dev container; how to override `VAULT_ADDR` and `VAULT_TOKEN` to point at an existing Vault cluster
  3. **Kubernetes target** — cloud kubeconfig assumption replaced by local-default; how to pass `kubeconfig-content` to retain a cloud target
  4. **Datadog and Dynatrace references removed** — guidance to integrate observability via a separate repository
  5. **`scripts/create-s3-bucket.sh` rename** to `create-state-bucket.sh` with backward-compatibility note for any external callers

**Given** the rewrite is complete
**When** I read §1 and §2 in sequence
**Then** the document reads as a unified migration narrative with the two top-level sections clearly distinguished
**And** any breaking-change subsections required by FR27 (Composite Action breaking changes) appear as inline sub-entries under whichever migration introduced them — none expected for MVP, but the slot is reserved with structure

**Given** the top-level `README.md` is rewritten in Story 5.3
**When** that README references migration
**Then** it anchor-links into specific subsections (e.g., `MIGRATION.md#state-backend-default`) so readers can jump directly to the relevant migration step

### Story 5.3: Rewrite top-level `README.md` for local-first quickstart and federation framing

As a prospect (Marcus) reading the repo cold,
I want the top-level `README.md` to convey the federated platform-ops model, the local-first quickstart from `git clone` to first dataplane, and the location of the companion API-team reference repository — readable in under 30 minutes,
So that I can decide whether to fork this repo as a starting point without running anything first.

**Acceptance Criteria:**

**Given** PRD FR34 (quickstart) and NFR19 (cold-readable in < 30 min)
**When** I rewrite the top-level `README.md`
**Then** the document opens with a one-paragraph framing of the federated platform-ops pattern (platform repo exposes Composite Actions; API-team repos consume them; the seam between them is the visible product)
**And** includes a "Quickstart" section presenting the local-first bootstrap as a sequential list of commands and expected outputs, taking the reader from `git clone` to a successfully provisioned team and deployed dataplane
**And** the Quickstart names the only required operator-supplied credential (`KONNECT_TOKEN` in `act.secrets`) per FR6
**And** includes a "Repository structure" section explaining `.github/actions/` (the public API surface consumed by API teams) vs. `.github/workflows/` (platform-operator-run only) as the structural security boundary
**And** includes a "Companion API-team reference repository" section with the link to that repo (URL TBD; section structure committed even if URL is a placeholder pending confirmation)
**And** links to per-action READMEs (the four / five published actions) and to `MIGRATION.md` (legacy → local + provider 3.1.0 → 3.15)
**And** briefly references the Flask onboarding webapp (`webapp/`) with a pointer to `webapp/README.md` (Story 5.4)

**Given** the rewrite is complete
**When** a reader unfamiliar with the repository reads the README cold (no other context)
**Then** they can answer these three questions from the README alone, in under 30 minutes:
  1. What is the federation seam between this repo and API-team repos?
  2. What commands do I run, in what order, to go from a fresh clone to a working dataplane?
  3. Where is the companion API-team repo I can look at to see the consumer side?

**Given** the rewrite is complete
**When** I check for vendor-specific identifiers
**Then** the README contains no Datadog / Dynatrace references and no real customer / partner identifiers (NFR7)

### Story 5.4: Verify Flask onboarding webapp produces schema-conformant output and document its usage

As an operator,
I want the bundled Flask webapp at `webapp/onboard_team_app.py` to produce team YAML output that passes the canonical YAML validator, and a `webapp/README.md` documenting how to run and use it,
So that FR23 is delivered as a real working capability and an operator can rely on the webapp output flowing into the provisioning pipeline without manual cleanup.

**Acceptance Criteria:**

**Given** the local stack is running and the webapp can be launched via the existing convention (e.g., `python3 webapp/onboard_team_app.py` or a documented `make webapp` target if one exists)
**When** I create or update `webapp/README.md`
**Then** the README documents: the webapp's purpose (thin operator UI for authoring/editing team YAML), launch instructions, the URL/port the UI is served on, what fields the form captures, and the expected output location/format

**Given** the webapp is running
**When** I author a sample team via the UI (e.g., a fictional `flight-operations-2` team) and save the output
**Then** the produced YAML conforms to the schema enforced by `provision-konnect-resources/scripts/validate-config.sh` (FR10) — i.e., `validate-config.sh` accepts the produced file with no errors

**Given** the webapp is running
**When** I edit an existing valid team YAML (e.g., `teams/flight-operations.yaml`) via the UI
**Then** the round-tripped output remains schema-conformant and preserves all original required fields

**Given** project-context.md's guidance ("keep business logic in shell scripts / Terraform — do not migrate Konnect logic into Python")
**When** I review the webapp scope after this story
**Then** the webapp is still strictly a thin operator UI — no Konnect API calls, no Vault access, no Terraform invocations from Python (any required scope-creep is flagged in the PR description rather than landed silently)
