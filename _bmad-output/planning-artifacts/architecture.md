---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/project-context.md
referenceSources:
  - /Users/jordi.fernandez/github/terraform-provider-konnect (Konnect Terraform provider source — CHANGELOG, docs, internal schemas; load-bearing for the 3.1.0 → 3.15 migration)
workflowType: 'architecture'
lastStep: 8
status: 'complete'
completedAt: '2026-05-06'
project_name: 'kw-platform-ops'
user_name: 'Jordi'
date: '2026-05-06'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements (34 total, 10 categories):**

The PRD's FRs partition into operator-facing capabilities (FR1–FR23: bootstrap, provisioning, deploy, publishing, portal, webapp), the public Action contract (FR24–FR28), and configuration-surface contracts (FR29–FR34: backend selection, migration, README quickstart). Operator-facing FRs are mostly already implemented — the refactor preserves them with different defaults underneath. The contract and configuration FRs are where genuinely new structure is introduced.

**Note:** FR30 and the related Tech-Success / MVP / risk-mitigation passages assume Konnect Vault as the default secrets backend. Per ADR #001 below, this is reverted: HashiCorp Vault remains the secrets backend in both default and alternative modes, differing only in deployment target (local docker-compose container vs. real cluster). The PRD passages are superseded by ADR #001; no PRD edit is being made — the architecture document is the authoritative source for design decisions.

**Non-Functional Requirements (19 total):**

Five NFRs dominate architectural choice:
- **NFR10** (`act`-runnable workflows, 100%) — bounds the toolchain to what runs on macOS via `act` with no hand-edits.
- **NFR15** (pluggable backend swaps via configuration alone) — forces clean abstractions across state and k8s target dimensions; secrets dimension collapses to a single env-var swap (see ADR #001).
- **NFR16** (Action contract stability across tagged releases) — promotes `.github/actions/` to a versioned API surface.
- **NFR4–NFR6, NFR9** (secret-handling discipline) — applied uniformly across every workflow and action.
- **NFR1, NFR3** (cold setup < 20 min, ≤ 4 GB / 4 vCPU idle) — caps local-stack complexity.

**Scale & Complexity:**

- Primary domain: DevOps / platform-engineering tooling (IaC + CI/CD + reusable Composite Actions).
- Complexity: medium overall; integration complexity dominates (many federated tools, two-sided contract, pluggable seams). Runtime complexity is low (no application).
- Estimated architectural components: ~6 — local stack (docker-compose with MinIO + HashiCorp Vault), state-backend abstraction, k8s-target abstraction, Composite Action contract layer, validation-gate pipeline, migration tooling. (Secrets-backend abstraction collapses into the local stack and the existing `vault` Terraform module — no new component needed.)

### Technical Constraints & Dependencies

- **Konnect SaaS control plane stays hosted** — only dataplanes are local. Defines the boundary of "local-first."
- **HashiCorp Vault remains the secrets backend** in both default and alternative modes (ADR #001). Local docker-compose Vault is a dev-mode container at `http://localhost:8300`; production users point `VAULT_ADDR` at their own cluster. Existing Vault paths and the `terraform/konnect-teams/modules/vault` module are retained.
- **Konnect Config Store** (`konnect_gateway_config_store` / `_secret`, per-control-plane runtime-secret store) is noted as a future capability but is **out of scope for this PRD** — see ADR #001.
- **`act` + `pantsel/gh-runner:latest`** is the required local CI substrate — anchors what actions can assume installable.
- **Composite Actions only** (no JS or Docker actions without strong reason). Action-bundled files referenced via `${{ github.action_path }}`.
- **Exact-pinned tooling at the integration surface:** `kong/konnect = 3.15` (Terraform provider), `decK v1.51.0`, Spectral OWASP ruleset `^2.0`. Pin updates are reviewed changes.

### Cross-Cutting Concerns Identified

1. **Backend selection** — two independent dimensions in this PRD (state, k8s target), each radiating through every workflow and Terraform module that touches the dimension. Secrets is *not* a backend-swap dimension (per ADR #001) — only a `VAULT_ADDR` connection-target change.
2. **Secret flow.** Local default: docker-compose HashiCorp Vault dev-mode container (`http://localhost:8300`, dev root token from `act.secrets`); production: real HashiCorp Vault cluster (operator-supplied `VAULT_ADDR` + token). Same Vault paths, same Terraform module, same provider — only the connection target changes. NFR4–NFR6 secret-handling discipline applied uniformly: only `KONNECT_TOKEN` and `VAULT_TOKEN` ever leave `act.secrets`; nothing echoed to logs.
3. **Validation gates** — YAML schema, Spectral OpenAPI lint, `terraform plan` consistency. NFR12 forbids bypass; new code integrates with the existing gate set.
4. **Action contract stability** — input/output names, defaults, behavior preserved across tags; README ↔ `action.yml` non-divergence (NFR18) requires an enforceable check.
5. **Migration safety** — provider bump (3.1.0 → 3.15), legacy → local defaults, observability removal land in coordinated sequence. Recommended sequence revised: provider bump → state backend (MinIO) → k8s target (local) → observability removal → docs. The "secrets backend" step from the PRD's original sequence drops out.
6. **Naming sanitization** — established `replace(lower(name), " ", "-")` (Terraform) and `tr '[:upper:]' '[:lower:]' | tr ' ' '-'` (Bash) patterns must survive the refactor.

### Architectural Decision Records (preview)

**ADR #001 — HashiCorp Vault retained; Konnect Config Store deferred.** Date: 2026-05-06.
- *Decision:* HashiCorp Vault remains the secrets backend in both default and alternative modes. The local default runs HashiCorp Vault in dev mode via the existing `docker-compose.yaml` service; production uses a real Vault cluster. Same provider, same module, same Vault paths — only `VAULT_ADDR` and the `VAULT_TOKEN` source differ.
- *Rejected alternative:* Replacing HashiCorp Vault with Konnect Config Store (`konnect_gateway_config_store`) as the default secrets backend, per the PRD's original framing.
- *Why rejected:* Konnect Config Store is scoped per control plane and resolves only at gateway runtime via `{vault://...}` references in plugin configs. It cannot serve CI/Terraform-time credentials such as system-account tokens, AWS keys, or the bootstrap `KONNECT_TOKEN` itself. Forcing a swap would require a parallel CI-time secrets backend anyway, defeating the "single-backend" goal.
- *Consequences:* (a) PRD passages framing Konnect Vault as the default are superseded by this ADR. (b) The "pluggable secrets backend" abstraction (NFR15 for the secrets dimension, FR30) collapses to an env-var change — no module rewrites. (c) Konnect Config Store remains available as a future capability for runtime gateway secrets per API team but is out of scope for this PRD.

## Foundation Inventory (substitutes for Starter Template Evaluation)

### Why this section is not a starter selection

`kw-platform-ops` is a **brownfield refactor** of an existing platform-engineering reference repository. There is no application runtime to bootstrap and no greenfield code generation; the architecture inherits and continues to use the existing scaffolding. This section catalogs that scaffolding so downstream architectural decisions have a stable baseline to refer back to.

### Inherited Scaffolding

**Repository structure** (preserved as a security and contract boundary):
- `.github/actions/<name>/` — reusable Composite Actions; the public API consumed by API-team repos.
- `.github/workflows/` — platform-operator-run workflows; not consumed by API-team repos.
- `terraform/<domain>/` — Terraform root modules and submodules (currently `terraform/konnect-teams/`).
- `konnect/<resource-type>/` — Konnect resource declarations (developer portal, dashboards).
- `teams/*.yaml` — per-team source-of-truth declarations.
- `portal/*.yaml` — developer-portal resource declarations.
- `scripts/<helper>.sh` — operator helper scripts.
- `charts/<chart-name>/` — custom Helm charts (currently `kong-config-exporter`).
- `webapp/` — thin Flask operator UI (kept; logic stays in Bash/Terraform).
- `test/apis/`, `test/provisioning/` — scenario-style integration scripts.

**Local execution stack** (docker-compose, already in `docker-compose.yaml`):
- **MinIO** (`quay.io/minio/minio:latest`) — S3-compatible Terraform state backend. Bucket `tfstate` auto-created by `minio-create-bucket` companion service.
- **HashiCorp Vault** (`hashicorp/vault`, dev mode) — secrets backend on `:8300`, root token `root`, file storage in `vault_data` volume.
- **`pantsel/gh-runner:latest`** — `act` runner image (referenced in `.actrc` / Makefile, not in compose).

**Toolchain pins** (from PRD §Tool / Version Stack Matrix):
- Konnect Terraform provider: `kong/konnect = 3.15` (target; current code still on `3.1.0`, ADR-pending).
- decK CLI: `v1.51.0`.
- Spectral CLI + OWASP ruleset: latest + `^2.0`.
- Helm chart `kong/kong`: default `2.45.0`.
- Kong Gateway image: default `3.11.0.2`.
- Standard GitHub Actions: `actions/checkout@v4`, `hashicorp/setup-terraform@v3`, `aws-actions/configure-aws-credentials@v4`, `azure/setup-helm@v4`, `azure/setup-kubectl@v4`.
- `yq` (mikefarah build), installed on demand by actions.

**Established patterns** (continue to apply in new code):
- Bash: `set -euo pipefail`, `shell: bash` declared on every composite-action step, OS detection via `uname -s` for binary downloads.
- Terraform: partial backend config (`config.s3.tfbackend` + `-backend-config=...`); `init -upgrade` → `plan -out=tfplan` → `apply tfplan`; `for_each` over `count` for collections keyed by name.
- Naming sanitization: `replace(lower(name), " ", "-")` (Terraform) / `tr '[:upper:]' '[:lower:]' | tr ' ' '-'` (Bash).
- Composite Actions only (no JS or Docker actions without strong reason); action-bundled files via `${{ github.action_path }}/...`.
- Secrets passed as explicit Action inputs from caller workflows; no `secrets: inherit`.

### What the architecture inherits *and refactors*

The next step (architectural decisions, step-04) addresses how the following are reshaped on top of this foundation:

- **State backend** abstraction (MinIO default ↔ AWS S3 alternative, configuration-only swap).
- **K8s target** abstraction (local OrbStack/Docker Desktop default ↔ cloud cluster alternative, configuration-only swap).
- **Konnect provider migration** (3.1.0 → 3.15 with state migration plan).
- **Composite Action contract layer** (versioning, README ↔ `action.yml` parity enforcement, breaking-change policy).
- **Observability removal** (Dynatrace/Datadog stripped from workflows, actions, charts, values, docs).

### Initialization

There is no `npm create` / `npx` / framework-init equivalent. The repository is consumed via:
1. **Cold clone:** `git clone <repo>` → `make prepare`.
2. **Fork** as a production starting point.
3. **Action reference** from API-team workflows (`uses: <org>/kw-platform-ops/.github/actions/<name>@<ref>`).

`make prepare` is the canonical bootstrap target and is documented in the top-level README.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- D1 — State backend abstraction strategy
- D3 — Konnect provider 3.1.0 → 3.15 migration approach
- D5 — Validation gate composition (bypass prevention)

**Important Decisions (Shape Architecture):**
- D2 — Kubernetes target abstraction
- D4 — Composite Action versioning & contract enforcement
- D6 — Observability removal cut line
- D7 — MIGRATION.md structure

**Already Decided / Inherited:**
- ADR #001 — HashiCorp Vault retained as secrets backend (step-2).
- Repository structure boundaries (step-3 Foundation Inventory).
- Toolchain pins: `kong/konnect = 3.15`, `decK v1.51.0`, Spectral OWASP `^2.0`, Helm chart `kong/kong = 2.45.0`, Kong image `3.11.0.2`, runner `pantsel/gh-runner:latest` (step-3).
- Composite Actions only; `${{ github.action_path }}` for bundled files (project-context).

**Standard categories that do not apply:**
- Data Architecture — no application database; source-of-truth is YAML in git, state in Terraform.
- Frontend Architecture — Flask webapp is a thin operator UI; logic stays in Bash/Terraform.

### D1 — State Backend Abstraction

**Decision:** Two committed `.tfbackend` files (`config.minio.tfbackend` for local default, `config.s3.tfbackend` for AWS), selected at workflow time by `TF_BACKEND_CONFIG` env var. `terraform init -reconfigure -backend-config="$TF_BACKEND_CONFIG"` performs the swap.

**Rationale:** Declarative; isolates backend-specific quirks (MinIO `force_path_style`, `skip_credentials_validation`, custom `endpoint` vs. AWS real IAM) in their own file; fits the partial-backend-config pattern already in the repo.

**Affects:** Every Terraform-touching workflow; `scripts/create-s3-bucket.sh` (renamed to `create-state-bucket.sh`, supports MinIO and AWS); the future shared Terraform-init composite action (see step-06).

### D2 — Kubernetes Target Abstraction

**Decision:** `deploy-dp/action.yml` declares two inputs:
- `kubeconfig-path` (default `~/.kube/config`) — used for local clusters and any operator with a host kubeconfig.
- `kubeconfig-content` (optional, secret) — raw YAML written to `${RUNNER_TEMP}/kubeconfig` when set.

If `kubeconfig-content` is set, it wins; otherwise the action exports `KUBECONFIG=<kubeconfig-path>`. No backend-specific code branching.

**Rationale:** Native k8s convention; works identically for OrbStack / Docker Desktop / EKS / GKE / AKS. Cloud-CI flows that lack a host kubeconfig pass content; local users pass nothing.

**Affects:** `deploy-dp/action.yml`, `deploy-dp/README.md`, every workflow that calls `deploy-dp`.

### D3 — Konnect Provider Migration (3.1.0 → 3.15)

**Decision:** Single-PR migration scoped to the repo's actual provider surface — `konnect_team`, `konnect_team_role`, `konnect_control_plane`, system-account / vault module resources. Diff against the local provider source at `/Users/jordi.fernandez/github/terraform-provider-konnect` per resource. Document required `terraform state mv` operations and any attribute renames in `MIGRATION.md` Section 2. Verification gate: `terraform plan` against a fresh local MinIO backend shows zero diffs.

**Rationale:** The repo uses a narrow subset of the provider; auditing four resource types is tractable. Big-bang is appropriate for this scope; incremental per-minor would be over-engineered for a single-engineer SE-demo asset.

**Affects:** `terraform/konnect-teams/providers.tf` (provider pin), every resource using a changed attribute, `MIGRATION.md`.

### D4 — Composite Action Versioning & Contract Enforcement

**Decision:**
1. **Ref strategy:** `@main` for MVP. Per-repo tagged releases (`v1.0.0`, `v1.1.0`) introduced in Growth phase when the asset graduates from demo to production-fork starting point.
2. **README ↔ `action.yml` non-divergence:** CI lint diffs each `action.yml`'s declared `inputs`/`outputs` against the corresponding README's input/output tables. Failure blocks merge. Implementation: small `yq | python` script in `.github/workflows/`.
3. **Breaking-change policy (FR27):** Any input rename, removal, or default change is a breaking change; documented in `MIGRATION.md` with a remediation example for callers.

**Rationale:** PRD accepts `@main` for the companion repo and the asset has a single engineer; per-action tags would be premature. The lint catches NFR18 drift mechanically; manual review alone is too brittle for a release-blocking concern.

**Affects:** `.github/actions/<name>/action.yml`, `.github/actions/<name>/README.md`, new `.github/workflows/lint-action-contracts.yaml`, `MIGRATION.md`.

### D5 — Validation Gate Composition

**Decision:** Per-workflow validation gates are retained (no centralization). Bypass prevention via a CI lint that flags `continue-on-error: true` or `|| true` patterns adjacent to step names matching `validate|lint|plan`. The YAML-schema validator stays in `provision-konnect-resources/scripts/validate-config.sh` and is invoked from both the action and the workflow.

**Rationale:** Gates are tightly coupled to their inputs; centralizing creates skip-temptation for "small changes." Mechanical bypass detection is the cheapest enforcement mechanism that holds.

**Affects:** New `.github/workflows/lint-no-bypass.yaml` (or step in an existing CI workflow); reaffirms `validate-config.sh` as the canonical validator.

### D6 — Observability Removal Cut Line

**Decision:** Remove everything in the codebase that names `datadog`, `dynatrace`, `dd-`, `dt-`, or vendor-specific telemetry endpoints — `values.yaml` keys, Helm overlays, action inputs, env vars, scripts, docs. Keep vendor-neutral observability scaffolding (Kong status endpoints, default log format, default Prometheus metrics exposition). Single PR, scoped via `git grep -i 'datadog\|dynatrace'`.

**Rationale:** Clear inventory boundary; preserves demo-relevant generic telemetry while removing the out-of-scope vendor surface.

**Affects:** `k8s/values.yaml`, any chart overlays, action inputs and READMEs, top-level README, `MIGRATION.md` (note for legacy users).

### D7 — MIGRATION.md Structure

**Decision:** Single `MIGRATION.md` with two top-level sections — *Migration 1 — Legacy cloud-only → local-first* and *Migration 2 — Konnect provider 3.1.0 → 3.15*. Per-Composite-Action breaking changes (FR27) appear as inline subsections under the relevant migration.

**Rationale:** PRD names both migrations; co-locating them is easier to skim and to maintain.

**Affects:** New `MIGRATION.md` at repo root, linked from top-level `README.md`.

### Decision Impact Analysis

**Implementation Sequence (revised from PRD risk-mitigation guidance):**
1. **Konnect provider 3.1.0 → 3.15** (D3) — riskiest schema work; do it before downstream changes can be verified. Verification gate `terraform plan` clean against fresh local backend.
2. **State backend abstraction** (D1) — MinIO default, S3 alternative; rename `create-s3-bucket.sh` → `create-state-bucket.sh`; introduce shared Terraform-init composite action (see step-06).
3. **K8s target abstraction** (D2) — additive `deploy-dp` input; non-breaking.
4. **Observability removal** (D6) — single PR, mechanical.
5. **Documentation refresh** — top-level README, per-action README parity, `MIGRATION.md`. Lands with action-contract lint (D4) and bypass lint (D5) in the same PR.

(Secrets-backend step from the PRD's original sequence drops out per ADR #001 — the `docker-compose.yaml` already runs HashiCorp Vault locally; no action required beyond ensuring `make prepare` brings it up.)

**Cross-Component Dependencies:**
- D1 + D5 → shared `init-terraform` composite action (introduced in step-06).
- D2 + D4 → new `deploy-dp` input bumps the contract; lint must accept the addition without flagging drift (lint diffs `action.yml` against README, so updating both in the same commit is the path).
- D3 + D5 → provider verification gate must run via `act` per NFR10; not a CI-only path.

## Implementation Patterns & Consistency Rules

### Inherited patterns (canonical source: project-context.md)

This architecture inherits the patterns codified in `_bmad-output/project-context.md` — Bash hygiene (`set -euo pipefail`, OS detection, no secret echoing), Terraform style (partial backend, `for_each` keying, `lookup(map, "key", default)`), Helm conventions (`--set` for runtime-injected values, `--values` for stable configuration), action input naming (kebab-case), workflow naming, env-var scoping, secrets handling (explicit input passing, no `secrets: inherit`), path safety via `${{ github.action_path }}`, and validation-as-quality-gate discipline. Those rules are not restated here; project-context.md is canonical.

### New patterns introduced by D1–D7

Six new conflict points are introduced by the architectural decisions in step-04. Each is named for the decision it derives from.

#### P1 — Backend-config file naming and selection (from D1)

- **File naming:** `config.<backend-name>.tfbackend` (e.g., `config.minio.tfbackend`, `config.s3.tfbackend`), in the same directory as the Terraform root module.
- **Selector env var:** `TF_BACKEND_CONFIG` holds the basename or path passed to `-backend-config=...`.
- **Init invocation:** `terraform init -reconfigure -backend-config="$TF_BACKEND_CONFIG"`. Always `-reconfigure` when the env var changes; never just `init`.
- **Anti-patterns:** sed/envsubst templating on a single backend file; switch logic inside HCL.

#### P2 — Paired alternative inputs to Composite Actions (from D2; generalized)

When a Composite Action accepts the same logical thing in two forms (path on disk vs. raw content), use the suffix convention `<thing>-path` and `<thing>-content`:

- If `<thing>-content` is set, write it to `${RUNNER_TEMP}/<thing>` and use that.
- Otherwise, use `<thing>-path` (with a sensible default where applicable).
- If both are set, `<thing>-content` wins.

Concrete instance: `deploy-dp` → `kubeconfig-path` (default `~/.kube/config`) and `kubeconfig-content` (optional, secret).

#### P3 — Validation step `name:` prefix (from D5)

Every step performing a validation gate uses a `name:` whose leading word is one of `Validate`, `Lint`, or `Plan`. The bypass-detection lint matches on `^(Validate|Lint|Plan)\b` in step names and verifies the step has neither `continue-on-error: true` nor `|| true` in `run:`. Renaming a gate step requires intent and is reviewable in a PR.

Examples:
- `name: Validate team YAML schema`
- `name: Lint OpenAPI with Spectral`
- `name: Plan Terraform changes`

#### P4 — Action README structure (from D4)

Every published Composite Action's `README.md` uses these H2 sections in this order (the contract lint diffs against this):

1. `# <action-name>` — title
2. `## Overview` — purpose paragraph
3. `## Inputs` — table with columns: `Name | Description | Required | Default`
4. `## Outputs` — table with columns: `Name | Description`
5. `## Side Effects` — what the action mutates (Konnect resources, Vault paths, k8s resources, files)
6. `## Example Usage` — complete `uses:` block with realistic input values
7. `## Failure Modes` — common errors and how the caller surfaces them

Inputs and Outputs tables must list every entry from `action.yml`'s `inputs:` / `outputs:` keys, with matching name, required flag, and default. Drift fails the contract lint.

#### P5 — MIGRATION.md entry format (from D7)

Each migration entry follows:

````markdown
### <Short title>

**Affected:** <files / resources / actions>

**Before:**
```<lang>
<previous form>
```

**After:**
```<lang>
<new form>
```

**Remediation:** <numbered steps or paragraph for users to apply>
````

Consistent format makes entries skimmable and lets the README anchor-link directly to specific migrations.

#### P6 — Terraform state-migration script convention (from D3)

- **Path:** `terraform/<domain>/migrations/NNN-<short-desc>.sh` (zero-padded sequential, e.g., `001-konnect-3-15-rename.sh`).
- **Header:** `set -euo pipefail` and a comment block stating purpose, source/target provider versions, prerequisites, idempotency notes.
- **Idempotent:** re-running on the same state must be safe. Guard every `terraform state mv` / `state rm` / `import` with a `terraform state list | grep` check.
- **Driver:** invoked via `make migrate-state`, which runs unapplied migrations in order. Applied marker file at `.terraform/migrations-applied` (gitignored).

### Enforcement

| Pattern | Enforcement |
|---|---|
| P1 — backend selection | Code review + shared `init-terraform` composite action (see step-06) makes the right thing the easy thing |
| P2 — paired inputs | Code review; `action.yml` schema declares both inputs with paired suffixes |
| P3 — validate/lint/plan prefix | Mechanical: bypass lint (D5) keys off the leading word |
| P4 — README structure | Mechanical: action-contract lint (D4) diffs README against `action.yml` |
| P5 — MIGRATION.md entries | Code review; existing entries are the canonical examples |
| P6 — state-migration scripts | `make migrate-state` driver + `set -euo pipefail` + idempotency reviewed in PR |

### Anti-patterns specific to this architecture

- **Hidden backend selection** (P1) — editing the `.tfbackend` file rather than swapping which one is referenced. Defeats reproducibility.
- **Backend branching in HCL or Bash** (P1, P2) — `if [ "$BACKEND" = "minio" ] then ...` is a smell. The abstraction lives at the configuration boundary, not inside code.
- **Validation steps without the P3 prefix** — silently bypasses the bypass detector. Equivalent to disabling the gate.
- **README-only or `action.yml`-only changes** (P4) — adding an input to `action.yml` without updating the README inputs table (or vice versa) fails the contract lint by design.
- **Non-idempotent state-migration scripts** (P6) — re-running on a clean checkout must succeed.

## Project Structure & Boundaries

### Two-Terraform-tree reality

The repo has **two** Terraform trees, both consumed by this architecture's decisions:

1. `terraform/konnect-teams/` — platform-team root module (teams, system accounts, Vault rooting).
2. `.github/actions/provision-konnect-resources/terraform/` — team-side root module (~30 submodules: APIs, portals, plugins, control planes, dashboards), consumed by the `provision-konnect-resources` action.

D1 (state backend), D3 (provider migration), P1 (`.tfbackend` naming), and P6 (state-migration scripts) apply identically to both.

### Target tree (post-refactor)

```
kw-platform-ops/
├── README.md                              ← rewritten for local-first quickstart (FR34)
├── MIGRATION.md                           ← NEW (FR32, FR33; D7)
├── Makefile                               ← extended: `migrate-state` target
├── docker-compose.yaml                    ← unchanged (MinIO + Vault already wired)
├── act.secrets.example                    ← NEW (template; act.secrets stays gitignored)
├── .actrc / .actrc.tpl                    ← unchanged
├── .gitignore                             ← unchanged
│
├── .github/
│   ├── actions/                           ← public API surface (FR24–FR28)
│   │   ├── init-terraform/                ← NEW shared composite (D1, D5)
│   │   │   ├── action.yml
│   │   │   └── README.md
│   │   ├── deploy-dp/
│   │   │   ├── action.yml                 ← extended: kubeconfig-path, kubeconfig-content (D2/P2)
│   │   │   ├── README.md                  ← NEW (FR25, P4)
│   │   │   └── k8s/kong-dp/values.yaml    ← Datadog/Dynatrace keys removed (D6)
│   │   ├── provision-konnect-resources/
│   │   │   ├── action.yaml                ← unchanged shape; consumes init-terraform
│   │   │   ├── README.md                  ← already present; updated to P4 structure if needed
│   │   │   ├── scripts/validate-config.sh ← canonical YAML validator (D5)
│   │   │   ├── terraform/
│   │   │   │   ├── providers.tf           ← provider pin → 3.15 (D3)
│   │   │   │   ├── backend.tf
│   │   │   │   ├── config.minio.tfbackend ← NEW (D1/P1)
│   │   │   │   ├── config.s3.tfbackend    ← retained as alt-path (D1)
│   │   │   │   ├── main.tf, variables.tf, schema.json, README.md
│   │   │   │   ├── modules/               ← ~30 existing submodules; schema diffs per D3
│   │   │   │   └── migrations/            ← NEW (D3/P6)
│   │   │   │       └── 001-konnect-3-15-rename.sh
│   │   ├── publish-api-configuration/
│   │   │   ├── action.yaml                ← unchanged shape
│   │   │   ├── README.md                  ← NEW (FR25, P4)
│   │   │   ├── spectral/.spectral.yaml
│   │   │   ├── kong-lint/kong.ruleset.yaml
│   │   │   ├── plugins/                   ← key-auth, oas-validation, openid-connect, prom, rate-limiting, request-termination
│   │   │   └── patches/select_tags.yaml
│   │   └── setup-k8s-tools/
│   │       ├── action.yaml                ← unchanged
│   │       └── README.md                  ← NEW (FR25, P4)
│   │
│   └── workflows/
│       ├── deploy-dp.yaml                 ← updated: TF_BACKEND_CONFIG, kubeconfig inputs
│       ├── developer-portal.yaml          ← updated: init-terraform usage
│       ├── onboard-konnect-teams.yaml     ← updated: init-terraform usage
│       ├── test-sync-api-configuration.yaml
│       ├── lint-action-contracts.yaml     ← NEW (D4: README ↔ action.yml diff)
│       └── lint-no-bypass.yaml            ← NEW (D5/P3: bypass detection)
│
├── terraform/
│   └── konnect-teams/                     ← platform-team root module
│       ├── providers.tf                   ← provider pin → 3.15 (D3)
│       ├── backend.tf
│       ├── config.minio.tfbackend         ← NEW (D1/P1)
│       ├── config.s3.tfbackend            ← retained as alt-path
│       ├── main.tf, variables.tf, outputs.tf
│       ├── files/empty.yaml
│       ├── modules/
│       │   ├── system-account/
│       │   └── vault/                     ← retained per ADR #001; VAULT_ADDR connects to compose Vault by default
│       └── migrations/                    ← NEW (D3/P6)
│           └── 001-konnect-3-15-rename.sh
│
├── konnect/
│   ├── developer-portal/config.yaml
│   └── dashboards/dashboard-config.yaml
│
├── teams/
│   ├── .gitkeep
│   └── flight-operations.yaml             ← canonical example team (NFR7)
│
├── portal/                                ← reserved for portal/*.yaml triggers (currently empty)
│
├── charts/
│   └── kong-config-exporter/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/cronjob.yaml
│
├── k8s/
│   └── values.yaml                        ← Datadog/Dynatrace keys removed (D6)
│
├── scripts/
│   ├── check-deps.sh
│   ├── check-vault.sh
│   ├── create-state-bucket.sh             ← RENAMED from create-s3-bucket.sh (D1); supports MinIO + AWS
│   ├── create-minio-bucket.sh             ← already used by docker-compose; retained
│   ├── deploy-dps.sh
│   ├── get-host-ip.sh
│   ├── load-test-flights.js
│   ├── prep-act-secrets.sh
│   ├── prep-actrc.sh
│   ├── setup-vault.sh
│   ├── vault-pki-setup.sh
│   └── test-dashboard-module.sh
│
├── test/
│   ├── apis/
│   │   ├── flights/openapi.yaml
│   │   └── routes/openapi.yaml
│   └── provisioning/
│       ├── validate-config_test.sh
│       └── fixtures/dashboard-missing-definition.yaml
│
└── webapp/                                ← thin Flask operator UI
    ├── onboard_team_app.py
    └── static/konnect.svg
```

(`WHAT_TO_CHANGE.md` is retained at repo root until the refactor lands and is removed on completion.)

### What's added / renamed / removed

| Change | Files | Driven by |
|---|---|---|
| **Add** `MIGRATION.md` | root | FR32, FR33, D7 |
| **Add** `act.secrets.example` template | root | FR6 |
| **Add** shared composite action `init-terraform/` | `.github/actions/init-terraform/{action.yml,README.md}` | D1, D5 |
| **Add** `lint-action-contracts.yaml` | `.github/workflows/` | D4, NFR18 |
| **Add** `lint-no-bypass.yaml` | `.github/workflows/` | D5, NFR12 |
| **Add** READMEs | `.github/actions/{deploy-dp,publish-api-configuration,setup-k8s-tools}/README.md` | FR25, P4 |
| **Add** `kubeconfig-path` / `kubeconfig-content` inputs | `.github/actions/deploy-dp/action.yml` | D2, P2 |
| **Add** `config.minio.tfbackend` | both Terraform trees | D1, P1 |
| **Add** `migrations/` directories + first state-mv script | both Terraform trees | D3, P6 |
| **Add** `migrate-state` target | `Makefile` | D3, P6 |
| **Rename** `create-s3-bucket.sh` → `create-state-bucket.sh` | `scripts/` | D1 |
| **Update** provider pin `3.1.0` → `3.15` | both `providers.tf` files | D3 |
| **Update** workflows for `TF_BACKEND_CONFIG` env, init-terraform usage, observability removal | `.github/workflows/*.yaml` | D1, D6 |
| **Update** README for local-first quickstart | `README.md` | FR34 |
| **Update** README parity to P4 structure where needed | `provision-konnect-resources/README.md` | D4, P4 |
| **Remove** Datadog/Dynatrace references | `k8s/values.yaml`, action inputs/READMEs, top-level docs | D6 |
| **Remove** `WHAT_TO_CHANGE.md` | root | Refactor work item; delete on completion |

### Architectural boundaries

- **Operator-vs-team-facing split** (security boundary, preserved):
  - `.github/workflows/` = platform-operator-run only.
  - `.github/actions/` = consumed by API teams and platform workflows; semver-stable input contract.
- **Both Terraform trees follow identical conventions** for backend selection (P1), provider pin (D3), migrations (P6), and init pattern (via shared `init-terraform` composite action).
- **Validation gate ownership:**
  - YAML schema: `provision-konnect-resources/scripts/validate-config.sh` (canonical), invoked from both action and workflow.
  - OpenAPI Spectral lint: `publish-api-configuration/spectral/.spectral.yaml`.
  - Terraform plan: per-workflow, via shared `init-terraform`.
  - All gates use the P3 step-name prefix and are checked by `lint-no-bypass.yaml`.
- **Secret-flow boundary (ADR #001):**
  - Local default: docker-compose Vault on `:8300`, root token from `act.secrets`. Only `KONNECT_TOKEN` is operator-supplied (FR6).
  - Production: `VAULT_ADDR` overridden, `VAULT_TOKEN` operator-supplied. Same Vault paths, same module.

### Requirements-to-structure mapping

| FR group | Lives in |
|---|---|
| FR1 (clone-to-runnable) | `Makefile` (`prepare`), `docker-compose.yaml`, `scripts/check-deps.sh`, `scripts/prep-act-secrets.sh`, `scripts/prep-actrc.sh` |
| FR2 (S3-compatible local state) | `docker-compose.yaml` (MinIO), `scripts/create-state-bucket.sh`, `*config.minio.tfbackend` |
| FR3 (`act` runner) | `.actrc`, `.actrc.tpl`, `scripts/prep-actrc.sh` |
| FR4 (dependency check) | `scripts/check-deps.sh` |
| FR5 (start/stop/reset local stack) | `Makefile`, `docker-compose.yaml` |
| FR6 (single external credential) | `act.secrets.example` (NEW), README quickstart |
| FR7–FR12 (Konnect provisioning) | `.github/workflows/onboard-konnect-teams.yaml`, `terraform/konnect-teams/**`, `teams/*.yaml`, `provision-konnect-resources/**` |
| FR13–FR16 (dataplane deploy) | `.github/actions/deploy-dp/`, `k8s/values.yaml`, `.github/workflows/deploy-dp.yaml` |
| FR17–FR20 (API publishing) | `.github/actions/publish-api-configuration/**`, `.github/workflows/test-sync-api-configuration.yaml` |
| FR21–FR22 (portal + dashboards) | `konnect/developer-portal/`, `konnect/dashboards/`, `.github/workflows/developer-portal.yaml`, `provision-konnect-resources/terraform/modules/portal_*` |
| FR23 (operator webapp) | `webapp/onboard_team_app.py` |
| FR24–FR28 (Action contract stability) | `.github/actions/*/README.md`, `.github/workflows/lint-action-contracts.yaml` |
| FR29 (state-backend select) | `*config.{minio,s3}.tfbackend`, `.github/actions/init-terraform/`, `TF_BACKEND_CONFIG` env var |
| FR30 (secrets-backend select) | `VAULT_ADDR` env var; `terraform/konnect-teams/modules/vault/` (per ADR #001 — same module both modes) |
| FR31 (k8s target select) | `.github/actions/deploy-dp/action.yml` (`kubeconfig-path`, `kubeconfig-content`) |
| FR32 (legacy → local migration) | `MIGRATION.md` § 1 |
| FR33 (provider 3.1 → 3.15 migration) | `MIGRATION.md` § 2, `*/migrations/001-konnect-3-15-rename.sh`, `Makefile` (`migrate-state`) |
| FR34 (README quickstart) | `README.md` |

### Integration points / data flow

1. **Operator clones repo** → `make prepare` → docker-compose brings up MinIO (`:9000`/`:9001`) + Vault (`:8300`); `prep-actrc.sh` writes `.actrc`; `prep-act-secrets.sh` ensures `act.secrets` has `KONNECT_TOKEN` and `VAULT_TOKEN=root`.
2. **Operator edits `teams/<team>.yaml`** → push to `main` triggers `onboard-konnect-teams.yaml` (or `act` runs it locally).
3. **`onboard-konnect-teams.yaml`** → calls `init-terraform` (selects backend via `TF_BACKEND_CONFIG`) → runs `validate-config.sh` (P3 prefix: "Validate ...") → `terraform plan -out=tfplan` (P3 prefix: "Plan ...") → `terraform apply tfplan` → `terraform/konnect-teams/` provisions teams, system accounts, Vault paths.
4. **API team workflow (companion repo)** → calls `provision-konnect-resources` action with team's per-team YAML → action runs its inner Terraform → provisions APIs, portals, plugins.
5. **Operator runs `deploy-dp.yaml`** with `kong-image-tag` + `helm-chart-version` inputs → action selects k8s target via `kubeconfig-content` (cloud) or `kubeconfig-path` default (local) → Helm installs `kong/kong` chart → dataplane registers with hosted Konnect.
6. **API team's `publish-api.yaml`** → calls `publish-api-configuration` action → Spectral OWASP lint (P3 prefix: "Lint ...") → decK syncs to dev portal.
7. **CI on every PR:** `lint-action-contracts.yaml` (D4) + `lint-no-bypass.yaml` (D5) run; failures block merge.

### Out-of-scope structural changes

- No new application code (no `src/`, no JS Action runtimes).
- `portal/` directory remains reserved/unpopulated; content lives in companion repo / future PRD.
- No CI test harness beyond `act` and the two new lint workflows; NFR10 makes `act` the integration test.
- No observability replacement after Datadog/Dynatrace removal — explicitly out of scope per PRD.

## Architecture Validation Results

### Coherence Validation ✅

All architectural decisions (D1–D7) and patterns (P1–P6) compose cleanly. One explicit supersession: ADR #001 supersedes PRD FR30's framing — secrets-backend "selection" is implemented as a `VAULT_ADDR` connection-target swap rather than as module-level abstraction. NFR15's config-only-swap intent is satisfied.

The bypass-detection lint (D5) requires existing workflow steps to either conform to the P3 `Validate|Lint|Plan` prefix or to be grandfathered explicitly — to be resolved as a sub-task when the lint ships.

### Requirements Coverage Validation

**Functional Requirements:** Full coverage with two acknowledged deferrals.
- FR26 (pin-to-tag stable contract): MVP commits to `@main`; per-repo tag releases land in Growth phase per D4. Aligns with the PRD's existing pluggable-backend deferral pattern.
- FR30 (secrets-backend selection): Reframed by ADR #001 — same NFR15 intent (config-only swap) via a different mechanism (env var instead of module abstraction).

**Non-Functional Requirements:** Full structural coverage. Performance NFRs (NFR1: cold setup < 20 min; NFR2: workflow < 5 min via `act`; NFR3: ≤ 4 GB / 4 vCPU idle) are structurally supported but not yet empirically measured; SE-validation is the acceptance gate per PRD risk-mitigation.

### Implementation Readiness Validation ✅

- Decisions documented with versions (toolchain pins from Foundation Inventory; D3 confirms `kong/konnect = 3.15`).
- Project structure complete and tied to FRs.
- Patterns address every conflict point introduced by the architecture; inherited rules cite project-context.md.
- Two new CI lints (D4 contract; D5 bypass) provide mechanical drift control.

### Gap Analysis Results

**Critical gaps:** None.

**Important gaps (acknowledged scope reductions, not blockers):**

1. FR26/NFR16 deferred to Growth phase (`@main` for MVP).
2. FR30 reframed by ADR #001; PRD remains as-is per user instruction; ADR #001 is authoritative.
3. P3 step-name conformance audit needed before `lint-no-bypass.yaml` ships — either rename non-conforming gate steps (preferred) or add a grandfather list.

**Nice-to-have (defer to implementation):**

4. Contract lint parser specifics (README table format, multi-line descriptions).
5. Migration applied-marker file format.
6. `make migrate-state` ordering across the two Terraform trees (outer first → inner).

**Areas for future enhancement:** per-action tag releases (closes FR26/NFR16); empirical NFR1/2/3 measurement; Konnect Config Store integration for runtime gateway secrets (per ADR #001).

### Architecture Completeness Checklist

**Requirements Analysis**
- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**Architectural Decisions**
- [x] Critical decisions documented with versions
- [x] Technology stack fully specified
- [x] Integration patterns defined
- [x] Performance considerations addressed

**Implementation Patterns**
- [x] Naming conventions established
- [x] Structure patterns defined
- [x] Communication patterns specified
- [x] Process patterns documented

**Project Structure**
- [x] Complete directory structure defined
- [x] Component boundaries established
- [x] Integration points mapped
- [x] Requirements to structure mapping complete

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION — with three explicitly acknowledged scope reductions (FR26/NFR16 deferred to Growth, FR30 reframed by ADR #001, P3 audit pending).

**Confidence Level:** High for technical decisions; medium-high overall (NFR1/2/3 structurally supported, not yet measured — SE validation is the acceptance gate).

**Key Strengths:**
- Brownfield reality respected; architecture inherits and refines.
- Federation seam preserved as a structural security boundary.
- ADR #001 dissolves the Konnect Vault primitive-coverage risk.
- D1 + D2 + D3 phased landing aligns with single-engineer constraint.
- Drift control mechanized for the two highest-leverage concerns (D4, D5 lints).

**Areas for Future Enhancement:**
- Per-action tag releases (closes FR26/NFR16).
- Empirical NFR1/2/3 measurement.
- Konnect Config Store integration for runtime gateway secrets.
- Companion API-team repo currency.

### Implementation Handoff

**AI Agent Guidelines:**
- Inherited rules live in `_bmad-output/project-context.md`; do not duplicate here.
- This architecture document is canonical for design decisions; ADR #001 supersedes PRD FR30 framing.
- Implementation sequence (per step-04 Decision Impact Analysis): Konnect provider 3.15 → state backend → k8s target → observability removal → docs refresh + lints. Each landable as an independent PR.

**First Implementation Priority:** Konnect provider 3.1.0 → 3.15 migration (D3) — inventory resources in both Terraform trees, schema-diff against local provider source, write `001-konnect-3-15-rename.sh` per tree, verify clean `terraform plan` against fresh local MinIO backend, write `MIGRATION.md` § 2.
