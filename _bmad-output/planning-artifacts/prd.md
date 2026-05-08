---
stepsCompleted: ['step-01-init', 'step-02-discovery', 'step-02b-vision', 'step-02c-executive-summary', 'step-03-success', 'step-04-journeys', 'step-05-domain-skipped', 'step-06-innovation-skipped', 'step-07-project-type', 'step-08-scoping', 'step-09-functional', 'step-10-nonfunctional', 'step-11-polish', 'step-12-complete']
status: complete
completedAt: '2026-05-06'
releaseMode: phased
inputDocuments:
  - _bmad-output/project-context.md
  - WHAT_TO_CHANGE.md
documentCounts:
  briefs: 0
  research: 0
  brainstorming: 0
  projectDocs: 1
  contextNotes: 1
classification:
  projectType: developer_tool
  projectSubtype: reference_implementation
  domain: devops_platform_engineering
  complexity: medium
  projectContext: brownfield
  primaryPersona: kong_solutions_engineer
shapingInsights:
  - local_first_with_pluggable_backends
  - pluggable_state_backend_minio_or_aws_s3
  - hashicorp_vault_sole_secrets_backend_local_docker_compose_or_remote_cluster
  - pluggable_k8s_target_local_orbstack_docker_desktop_or_cloud
  - konnect_saas_stays_hosted
  - observability_dynatrace_datadog_out_of_scope
  - konnect_provider_bump_3_1_0_to_3_15
  - new_features_deferred
workflowType: 'prd'
lastEdited: '2026-05-07'
editHistory:
  - date: '2026-05-07'
    changes: 'Reconcile FR30 + §Technical Success bullet + 17 related references with Architecture ADR #001 — HashiCorp Vault retained as sole secrets backend (local docker-compose Vault dev container default; real Vault cluster via VAULT_ADDR/VAULT_TOKEN swap for production). Konnect Vault declared out of scope. Affects: frontmatter shapingInsights, Executive Summary (×3), Success Criteria → Technical Success, Measurable Outcomes table, Journey 1 + 2 capabilities + narratives, Journey Requirements Summary, Tool/Version Stack Matrix (rows + closing note), Product Scope MVP item #2, Post-MVP Pluggable backend abstraction, Migration Guide §1 default-path swap, Risk Mitigation strategy, FR8, FR30, NFR9, NFR15.'
---

# Product Requirements Document - kw-platform-ops

**Author:** Jordi
**Date:** 2026-05-06

## Executive Summary

**kw-platform-ops** is a canonical reference implementation of federated platform-ops on Kong Konnect, runnable end-to-end on a MacBook with no cloud accounts. The repository is the *platform-team* half of a federated setup: it owns Konnect tenancy, team provisioning, dataplane deployment, dev portal configuration, and decK-driven API publishing — exposed as reusable composite GitHub Actions. Companion *API-team* repositories own their OpenAPI specs and consume those Actions; the contract between platform and API teams is the visible product.

The primary user is the Kong Solutions Engineer (or Sales Engineer) demoing federated platform-ops to a prospect. They clone the repo, run `make`, and within minutes are walking the prospect through both sides of the federation seam — using `act` to execute workflows locally, MinIO as the Terraform state backend, a local docker-compose HashiCorp Vault dev container for secrets, and a local Kubernetes cluster (OrbStack / Docker Desktop) for dataplanes. Konnect itself remains the hosted SaaS control plane.

The repository is currently stale and blocked by external-infrastructure setup friction (real AWS S3, real HashiCorp Vault, cloud Kubernetes). The work covered by this PRD removes that friction, modernizes the toolchain (Konnect Terraform provider 3.1.0 → 3.15), and removes out-of-scope observability vendor references (Dynatrace, Datadog) that belong in a separate repository. New features are explicitly out of scope; this is a localization, modernization, and clarity refactor that preserves existing behavior while making the asset usable again.

### What Makes This Special

The federation pattern *is* the product. Most platform-ops examples are monolithic — a single repo that does everything, which obscures the hardest question in platform engineering: *what is the contract between the platform team and the API teams?* This repo answers that question with running code, on both sides of the seam, on a single laptop.

Three deliberate design choices reinforce that focus:

1. **Federation is structural, not aspirational.** The platform repo exposes Actions; API-team repos consume them. There is no shortcut path that mixes concerns — an SE walking a prospect through the code is walking through a real federation boundary.
2. **Local-first execution is the price of admission.** A demo that doesn't run on the SE's laptop doesn't get demoed. Replacing AWS S3 with MinIO, a remote HashiCorp Vault cluster with a local docker-compose Vault dev container, and cloud Kubernetes with OrbStack/Docker Desktop turns a brittle cloud-dependent asset into a portable demo.
3. **Backends are pluggable, so the demo evolves into production.** State storage (MinIO ↔ AWS S3) and Kubernetes targets (local ↔ cloud) are abstracted as swappable providers; the secrets backend is HashiCorp Vault throughout (per ADR #001), with the connection target swapping between a local docker-compose Vault dev container and a real Vault cluster via `VAULT_ADDR`. The same code patterns that drive the laptop demo also drive a real production deployment — the prospect can fork the repo as a starting point, not a throwaway sandbox.

The core insight: a federated platform's value lives at the *seam* between the platform team and API teams. The reference implementation must show both sides of that seam, must run where the SE actually works (a MacBook), and must scale into production without code rewrites. Localization is the price of admission; federation is the lesson.

## Project Classification

- **Project Type:** Developer tool / reference implementation (with operator-tooling characteristics — Make targets, GitHub Actions, shell scripts).
- **Domain:** General — DevOps / platform engineering tooling. No regulated-industry concerns; complexity arises from multi-tool federation (Kong Konnect, decK, Terraform, Helm, GitHub Actions, Vault, MinIO/S3, `act`), not from the domain.
- **Complexity:** Medium. Established tooling, but the federation across many tools combined with the strict local-execution constraint introduces real coordination complexity.
- **Project Context:** Brownfield. Existing repository with significant in-place restructuring. The PRD bounds the immediate scope to localization, modernization, and observability removal; future feature work is explicitly deferred.
- **Primary Persona:** Kong Solutions Engineer / Sales Engineer demoing to prospects on a MacBook. Secondary personas: Kong customers evaluating federated platform-ops patterns, internal Kong engineers iterating on the reference implementation.

## Success Criteria

### User Success

The Kong Solutions Engineer is the success-defining user. Success means:

- **Clone-to-first-dataplane on a clean MacBook in under 20 minutes**, including dependency install via `make prepare`. No cloud accounts, no shared Vault, no kubeconfig handed in by IT.
- **Live demo of the federation seam without slides.** The SE can switch between this repo and a companion API-team repo, run a workflow live (push-to-deploy a dataplane, publish an API spec via decK), and explain *why* the boundary is drawn where it is — entirely from running code and `act` execution.
- **Recovery in seconds when something goes wrong on stage.** A failed `terraform plan` or a misconfigured YAML produces a readable error and a documented one-line fix; the SE never resorts to "let me show you a screenshot instead."
- **Provider-swap demonstration on demand.** When a prospect asks *"can this run on AWS S3 / HashiCorp Vault / EKS?"*, the SE flips a single config knob (or comments-in an alternative provider block) and proceeds with the demo. No code rewrite.

### Business Success

This repo is a GTM enablement asset, so business success is measured at the SE motion, not at runtime traffic:

- **Demo coverage:** ≥ 50% of Kong Konnect platform-ops prospect demos delivered using this repo within 3 months of the refactor landing; ≥ 80% within 6 months *(targets TBD with SE leadership)*.
- **Customer forks / references:** Measurable count of customer-side forks or links from customer conversations into this repo. Proxy signal that the asset survived the demo and became a starting point.
- **SE preparation time reduced.** Time from "I need to demo this" to "demo is running" drops from hours (current state — set up AWS, Vault, K8s) to minutes (clone, `make prepare`).
- **Asset is referenced in Kong's external content** — at least one published example in Kong docs, a Konnect blog post, or a recorded walkthrough — within 6 months of landing *(milestone TBD)*.

### Technical Success

The refactor has shipped successfully when all of the following are true:

- **Zero hard dependency on third-party cloud infrastructure in the default path.** No AWS account, no HashiCorp Vault cluster, no cloud Kubernetes required for the documented happy path.
- **Konnect Terraform provider on `kong/konnect = 3.15`** (latest), with all existing resources continuing to plan and apply cleanly. State migration from 3.1.0 documented; no breaking changes left unhandled.
- **All platform workflows run successfully via `act` on macOS** (`onboard-konnect-teams`, `developer-portal`, `deploy-dp`, `test-sync-api-configuration`, `publish-api-configuration`). 100% pass rate on a clean checkout.
- **HashiCorp Vault is retained as the sole secrets backend** per Architecture ADR #001. Default path runs HashiCorp Vault as a local docker-compose dev container at `:8300`; production overrides `VAULT_ADDR` (and `VAULT_TOKEN`) to point at a real Vault cluster. Same provider, same module, same paths — only the connection target changes. Konnect Vault is out of scope.
- **MinIO replaces AWS S3** as the Terraform state backend in the default path. The `scripts/create-s3-bucket.sh` flow works against MinIO with no code branching at the call site. AWS S3 remains supported as a swappable provider.
- **Local Kubernetes target supported** for dataplane deploys (OrbStack / Docker Desktop). Cloud K8s remains supported as a swappable target.
- **Dynatrace and Datadog references fully removed** from workflows, actions, charts, values files, and documentation. No vendor-specific observability code remains.
- **Functional parity with current behavior.** Existing capabilities (team provisioning, dataplane deployment, dev portal config, decK API publishing, OpenAPI Spectral linting) continue to work end-to-end.

### Measurable Outcomes

| Outcome | Current State | Target |
|---|---|---|
| Cloud accounts required for default demo | AWS + (optional) Vault SaaS + cloud K8s | 0 |
| Time from clean MacBook clone to first dataplane deployed | hours (varies; often blocked) | < 20 min |
| Konnect provider version | `3.1.0` | `3.15` |
| Platform workflows runnable via `act` on macOS | partial | 100% |
| Backend swap (MinIO ↔ S3 state; local Vault ↔ remote Vault cluster; local ↔ cloud K8s) documented | no | yes, single-knob swap |
| Dynatrace / Datadog references in repo | present | 0 |
| Documented federation seam (platform repo ↔ API-team repo example) | no companion example | yes |

## User Journeys

### Journey 1 — Sofia, Solutions Engineer: First Demo on a Tuesday Morning (Happy Path)

**Persona.** Sofia is a Kong SE based in Munich. She's been at Kong for fourteen months and supports a portfolio of mid-market prospects. She's comfortable with Konnect concepts but has avoided demoing platform-ops live because the legacy version of this repo required a half-day of AWS account setup and a kubeconfig from her account engineer. Today, she has a 10:00 AM call with a prospect's platform-engineering lead who explicitly asked: *"show me how a federated platform-ops setup works in practice."*

**Opening scene.** It's 9:15 AM. Sofia opens her MacBook on a hotel desk in Stockholm. No corporate VPN. No AWS console. She has thirty minutes to get a runnable demo.

**Rising action.** She runs `git clone` and `make prepare`. The Makefile checks dependencies (Docker, `act`, `gh`, `terraform`, `helm`, `kubectl`), brings up MinIO + the GitHub Actions runner + a HashiCorp Vault dev container via `docker-compose`, all on her laptop. She sets `KONNECT_TOKEN` in `act.secrets`, runs `make` to validate the YAML for `teams/flight-operations.yaml`, and watches `act` execute `onboard-konnect-teams.yaml` against her tenant. Twelve minutes in, the team exists in Konnect. She runs `deploy-dp` against her local OrbStack cluster — Helm pulls `kong/kong`, the dataplane comes up, and she sees it register with the hosted Konnect control plane.

**Climax.** At 9:52 AM, she has a working dataplane, a provisioned team, and a published API spec — entirely on her laptop. She rehearses the talk-track once: *"This is the platform repo. The Actions you see in `.github/actions/` — that's the contract. An API team's repository looks like this..."* and opens the companion API-team repo as a second tab.

**Resolution.** At 10:00 AM, she runs the demo live. When the prospect asks *"so the platform team owns the dataplane lifecycle and we just push our specs?"*, she answers by running an actual `act` invocation that triggers `publish-api-configuration` from the API-team repo against her platform stack. The prospect's platform lead asks for the GitHub URL before the call ends.

**Capabilities revealed.**
- **Frictionless local bootstrap** — `make prepare` must work on a clean macOS machine in under 20 minutes, with all dependencies declared and self-installed where feasible.
- **Minimal credential surface** — `KONNECT_TOKEN` (and Konnect server URL) plus a local `VAULT_TOKEN=root` for the docker-compose dev Vault (template-supplied via `act.secrets.example`); no AWS keys, no kubeconfig handoff.
- **Local stack via docker-compose** — MinIO, runner, and any helper services come up with one command.
- **`act`-runnable workflows on macOS** — every platform workflow must execute end-to-end via `act` without hand-edits.
- **Local k8s integration** — `deploy-dp` works against OrbStack / Docker Desktop with no cloud-specific assumptions.
- **Companion repo / federation seam visibility** — the SE needs a tangible "other side" to switch to during the demo.

### Journey 2 — Sofia, Solutions Engineer: Mid-Demo Provider Swap (Edge Case)

**Opening scene.** Different prospect, two weeks later. The prospect's lead architect interrupts the demo: *"This is great, but we already standardize on AWS S3 for Terraform state and HashiCorp Vault for secrets. Will this still work for us, or is it a laptop-only toy?"*

**Rising action.** Sofia stays calm. She switches to her terminal, edits a single configuration knob (env var, `.tfvars`, or workflow input — TBD by implementation), pointing the state backend at the prospect's preferred provider's S3-compatible storage and the secrets backend at HashiCorp Vault. She re-runs `terraform init -reconfigure` and the same `apply` pipeline that just ran against MinIO + the local docker-compose Vault now runs against the prospect's stack. No code changes. The Terraform plan output is identical except for the backend.

**Climax.** The architect's posture changes. *"So the same pipeline can run against either backend?"* — yes. *"And if we want EKS instead of local k8s?"* — Sofia changes the `kubeconfig` env var, points `deploy-dp` at the cloud cluster, and the same Helm-driven rollout proceeds.

**Resolution.** The prospect goes from skeptical-of-the-demo to *"can we get a copy of this repo as our starting point?"*. The architect asks how a real customer would extend it — opening the door to a follow-up implementation conversation.

**Capabilities revealed.**
- **Pluggable state backend** — single configuration knob to swap MinIO ↔ AWS S3 (or any S3-compatible). No call-site code changes.
- **Pluggable secrets-backend connection** — `VAULT_ADDR` (and `VAULT_TOKEN`) env-var swap from the local docker-compose Vault dev container to a real HashiCorp Vault cluster. Same provider, same module, same paths — only the connection target changes (per ADR #001).
- **Pluggable Kubernetes target** — `deploy-dp` action accepts a kubeconfig / context input that works equally for local clusters and cloud clusters.
- **Documented swap procedures** — README and per-action READMEs document the exact one-line/one-flag swap for each backend, so the SE can find and execute it without re-reading code.
- **Identical happy path across backends** — provider swaps must produce equivalent functional behavior; failure modes that only surface in one backend are documented.

### Journey 3 — Marcus, Prospect's Platform Lead: Post-Demo Evaluation

**Persona.** Marcus runs the platform-engineering team at a mid-market e-commerce company. After Sofia's demo, he walks back to his desk with the GitHub URL. His team has been wrestling for six months with how to give twenty API teams self-service access to a Konnect tenant without a central bottleneck. Sofia's demo showed him the *shape* of an answer — now he needs to know whether this asset is a real starting point or just a marketing surface.

**Opening scene.** Marcus forks the repo. He doesn't run `make prepare` — instead, he reads. He opens `README.md`, then `.github/workflows/`, then `.github/actions/deploy-dp/action.yml`, then `terraform/konnect-teams/main.tf`. He's looking for the seams.

**Rising action.** He notices the `.github/actions/` directory exposes everything an API team would need — `provision-konnect-resources`, `publish-api-configuration`, `deploy-dp` — with explicit, documented inputs. He opens the companion API-team example repo in a second tab and follows the call: API team's workflow `uses: kong/kw-platform-ops/.github/actions/publish-api-configuration@main` with their OpenAPI spec as input. *That's the contract.* He reads the action's README, sees inputs, outputs, an example caller, and a note about Spectral linting.

**Climax.** Marcus runs `make prepare` on his own MacBook. Twelve minutes later he's deployed a test team and a dataplane. He swaps the state backend to his company's existing S3 bucket and the secrets backend to their existing HashiCorp Vault. The same pipeline runs. He concludes: *"this is forkable. We can start from this and harden it for production."*

**Resolution.** He shares the repo with his team's tech lead. They agree to pilot it for one of the API teams as a 2-week experiment. Sofia hears about it three weeks later.

**Capabilities revealed.**
- **Self-explanatory codebase** — directory layout, action READMEs, and inline documentation must be navigable in a 30-minute reading pass; the federation contract must be visible without running anything.
- **Stable, documented Action input contracts** — every reusable Action needs a README documenting inputs, outputs, and an example caller workflow (the `provision-konnect-resources` pattern).
- **Companion API-team example repository** — a separate, publicly-readable repo that demonstrates the consumer side of the federation contract, referenced from this repo's README.
- **Production-evolvable patterns** — the local-default code is the same code that runs in production with different backend configuration; nothing needs rewriting to harden.
- **Clean separation of operator vs. team-facing surfaces** — `.github/workflows/` (platform-operator-run) vs. `.github/actions/` (consumed by API teams) preserved as a structural boundary that Marcus can point to when explaining the model to his team.

### Journey 4 — Priya, API-Team Developer: Federation in Action

**Persona.** Priya is a backend developer on the Flight Operations API team at a fictional Kong customer. Her team owns the `flights-api` OpenAPI spec. She has never logged into Konnect directly. She doesn't know what Terraform is, beyond the name.

**Opening scene.** Priya updates the OpenAPI spec in her team's repository to add a new `GET /flights/{id}/manifest` endpoint. She opens a PR.

**Rising action.** Her team's `publish-api.yaml` workflow runs. It calls `uses: kong/kw-platform-ops/.github/actions/publish-api-configuration@main` with her spec as input. The action's Spectral lint step runs the OWASP ruleset; she sees a clear pass/fail directly in her PR's check summary. After the merge, the workflow re-runs on `main`, decK syncs the change to the dev portal, and the new endpoint appears in the Konnect-hosted API catalog.

**Climax.** Priya never touches Konnect, never touches Vault, never knows MinIO exists. She owns her spec; the platform team owns everything else. The federation seam is invisible to her — which is the point.

**Resolution.** She moves on with her day. The platform-team contract did its job by being unobtrusive.

**Capabilities revealed.**
- **Action input contracts must be developer-friendly** — input names, error messages, and examples need to be readable by someone who has no platform-engineering context.
- **PR-time feedback** — Spectral linting (and any other validation) must surface failures clearly in GitHub's PR check view; failures must be actionable, not log dumps.
- **No platform-team credentials leak into API-team repos** — Konnect tokens, Vault tokens, and AWS keys live only in the platform repo's caller workflow or in repository-level secrets the platform team controls; the API-team repo only needs its own GitHub credentials.
- **decK sync is automatic and idempotent** — the post-merge sync step must not require API-team intervention, and re-running it on an unchanged spec must be a no-op.

### Journey Requirements Summary

The four journeys converge on **seven capability areas** the PRD must specify in detail:

1. **Frictionless local bootstrap** — `make prepare`, docker-compose stack, dependency self-discovery, < 20 min to first dataplane.
2. **Pluggable backends with single-knob swap** — state (MinIO ↔ AWS S3), secrets (local docker-compose Vault ↔ remote HashiCorp Vault cluster, same provider per ADR #001), Kubernetes (local ↔ cloud), each with documented swap procedure.
3. **Konnect-only credential surface in the default path** — only `KONNECT_TOKEN` and server URL required from the SE for the local demo.
4. **`act`-compatible workflows** — every platform workflow runs end-to-end on macOS via `act` with no hand-edits.
5. **Companion API-team reference repository** — a public, readable consumer of the federation contract; referenced from this repo's README; the federation seam made visible.
6. **Self-explanatory documentation surface** — top-level README rewrite, per-action README parity, example callers for every reusable Action; readable in a 30-minute pass.
7. **PR-time validation feedback** — Spectral linting (and any other gates) surface clean, actionable failures in GitHub PR checks for API-team developers consuming the Actions.

## Developer-Tool / Reference-Implementation Specific Requirements

### Project-Type Overview

`kw-platform-ops` is a **reference-implementation repository**, consumed in two distinct ways depending on persona:

1. **Fork-and-run** by Kong Solutions Engineers (primary persona) and prospective customers evaluating the federated platform-ops pattern. The repository's value as a fork is in its readability, runnability on a MacBook, and the visibility of the federation seam.
2. **Action reference** by API-team repositories (companion / consumer pattern). API-team workflows declare `uses: kong/kw-platform-ops/.github/actions/<name>@<ref>` and pass spec/team inputs; the repo's reusable Composite Actions form a stable contract.

These two modes together define the product surface. Neither is optional.

### Tool / Version Stack Matrix

The reference stack is pinned and explicit. Drift here is a regression.

| Tool | Pin / Version | Notes |
|---|---|---|
| Konnect Terraform provider (`kong/konnect`) | `3.15` | Bumped from `3.1.0`; latest at refactor time. Exact pin — no `~>`. |
| Terraform CLI | `latest` (via `hashicorp/setup-terraform@v3`) | `init -reconfigure` supported for backend swaps. |
| decK CLI | `v1.51.0` | Pinned in `publish-api-configuration`. |
| Spectral CLI (`@stoplight/spectral-cli`) | latest, OWASP ruleset `^2.0` | Lint gates must not be bypassed. |
| Helm | `azure/setup-helm@v4` | Chart `kong/kong` (not `kong/kong-gateway`). |
| Helm chart (`kong/kong`) | default `2.45.0` (overridable) | Chart version independent of image tag. |
| Kong Gateway image | default `3.11.0.2` (overridable) | Operator-set per `deploy-dp` invocation. |
| `kubectl` | `azure/setup-kubectl@v4` | Targets local (OrbStack/Docker Desktop) or cloud cluster. |
| AWS provider (Terraform) | `eu-central-1` defaults | Used only when state backend = AWS S3. |
| `act` runner image | `pantsel/gh-runner:latest` | Required for parity with this repo's actions. |
| `yq` | latest (mikefarah build) | Installed on demand by actions. |
| MinIO | `docker-compose`-managed (default local backend) | Replaces real AWS S3 in default path. |
| HashiCorp Vault | docker-compose dev container (local default, `:8300`) or real cluster (production, operator-supplied `VAULT_ADDR` + `VAULT_TOKEN`) | Sole secrets backend per ADR #001. Same provider, same paths; only the connection target changes. Konnect Vault is out of scope. |
| Local Kubernetes | OrbStack or Docker Desktop | Default `deploy-dp` target. |
| Python (Flask onboard webapp) | system Python 3 | Thin operator UI; logic stays in Bash/Terraform. |

The pluggable backends each have **two** valid configurations: state (MinIO ↔ AWS S3) and Kubernetes (local ↔ cloud) are vendor-pluggable; the secrets backend (HashiCorp Vault, sole vendor per ADR #001) is connection-pluggable (local docker-compose Vault ↔ real Vault cluster, same provider). The PRD considers a backend "supported" only when both configurations work end-to-end.

### Consumption / Installation Methods

There is no `npm install` equivalent. Consumption happens in three modes:

1. **Cold-clone for local execution.**
   - `git clone <repo>` → `make prepare` → ready to run platform workflows via `act`.
   - Single hard requirement from the user: a `KONNECT_TOKEN` for an accessible Konnect tenant. All other secrets are local or generated.
   - Documented in the top-level README quickstart.

2. **Fork as a production starting point.**
   - User forks the repo and swaps the default backends (state, secrets, k8s) to their production providers via the documented swap procedure.
   - Hardening checklist in the README points users at what to change for production (real S3 bucket, real Vault cluster, cloud k8s, secret rotation, etc.).

3. **Action reference from API-team workflows.**
   - API-team repository workflow declares `uses: <org>/kw-platform-ops/.github/actions/<action-name>@<ref>` for one of the published Composite Actions: `provision-konnect-resources`, `publish-api-configuration`, `deploy-dp`, `setup-k8s-tools`.
   - `<ref>` should be a tag or SHA in production usage; `main` acceptable for the reference companion repo.
   - The platform repo treats every published Action as a stable input contract — see API Surface below.

### API Surface — GitHub Actions Input Contracts

The Composite Actions in `.github/actions/` constitute the platform team's **public API**. Stability and documentation discipline here are non-negotiable, because API-team repos depend on them.

#### Published Actions (the contract)

| Action | Purpose | Consumer |
|---|---|---|
| `provision-konnect-resources` | Create / update Konnect resources (teams, control planes, APIs) from declarative YAML | Platform workflows; alt-callable from API-team repos for self-serve resource creation |
| `publish-api-configuration` | Lint OpenAPI (Spectral), encode for decK, sync to Konnect dev portal | API-team workflows |
| `deploy-dp` | Deploy a Kong Gateway dataplane via Helm against a configured k8s target | Platform workflows; alt-callable for team-scoped rollouts |
| `setup-k8s-tools` | Install kubectl + helm at consistent versions | Platform & team workflows |

#### Action contract requirements

- **Inputs.** Every action declares all inputs in `action.yml` with `description` and `required` fields. Optional inputs declare `default`. Defaults must match the **local-first** path (e.g., `aws-region: 'eu-central-1'` only when AWS path is selected; `konnect-region: 'eu'` and `konnect-server-url: 'https://eu.api.konghq.com'` always).
- **Outputs.** Actions that produce identifiers downstream (e.g., team IDs, control-plane IDs, dataplane endpoints) declare them as outputs — never via `$GITHUB_ENV` only.
- **Naming.** Inputs are kebab-case (`kong-image-tag`, `helm-chart-version`, `konnect-server-url`). Inputs are semver-stable; renames or removals are breaking changes that bump the action's documented contract.
- **Secrets.** Secrets are passed explicitly as inputs by the caller workflow — no `secrets: inherit`. Inside the action, they are exported to `$GITHUB_ENV` only when downstream steps need env-style access; never echoed to logs.
- **Path safety.** Action-bundled files (rulesets, plugin templates, Helm overlays) are referenced via `${{ github.action_path }}/...`; relative paths are forbidden.

#### Action README parity

Every published action ships a `README.md` documenting:
- Inputs (name, description, required, default).
- Outputs (name, description, type).
- Example caller workflow (a copy-pasteable `uses:` block with realistic input values).
- Side effects (what state in Konnect / Vault / k8s the action mutates).
- Failure modes (common errors and how the caller surfaces them).

The `provision-konnect-resources` README is the canonical pattern; all action READMEs must match its structure.

### Code Examples

Examples are first-class scope, not optional content:

- **Companion API-team reference repository (out of scope, exists separately).** A companion repository that consumes `publish-api-configuration` and `provision-konnect-resources` from a realistic API-team workflow already exists as a separate work stream. This PRD's responsibility ends at preserving the Action contracts that companion repository consumes (see FR24–FR28 and the Action contract preservation MVP item). Updates to the companion repository itself are explicitly out of scope per the Product Scope section, and the platform repo's top-level README links to the companion repository so the federation seam is visible to readers.
- **Per-action README example callers.** Each action's README includes a complete `uses:` block with realistic inputs that an SE or API-team developer can copy directly into a new workflow.
- **`teams/*.yaml` and `portal/*.yaml` example resources.** The fictional `flight-operations` team and its associated portal/API resources serve as the canonical multi-resource example. These are kept clean (no real customer data) and demonstrate every supported optional field at least once.
- **Make targets as runnable demos.** `make prepare`, `make test-validator`, and any other documented Make targets behave as executable examples; their stdout is curated to read as a guided walkthrough.

### Migration Guide

The refactor introduces two migrations that consumers of prior versions need to navigate. Both must be documented in the PRD scope.

#### Migration 1 — Legacy cloud-only → local-first

For users running the previous (pre-refactor) version of this repo against AWS + HashiCorp Vault + cloud k8s:

- **Default-path swap.** New default is MinIO + local docker-compose HashiCorp Vault + local k8s. Documented procedure for users who want to *retain* the cloud-backed configuration: point Terraform state at AWS S3 via `TF_BACKEND_CONFIG`, override `VAULT_ADDR` (and `VAULT_TOKEN`) to a real Vault cluster, and pass a cloud kubeconfig to `deploy-dp` via `kubeconfig-content`.
- **Removed components.** Dynatrace and Datadog references are gone. Users relying on those for observability must integrate via a separate repository / pipeline; PRD calls out that these are intentionally out of scope.
- **Renamed / restructured paths.** Any directory or file moves required by the refactor are listed in a `MIGRATION.md`. Where possible, structural moves are deferred to minimize churn for fork holders.
- **Behavioral parity guarantee.** Functional capabilities (team provisioning, dataplane deploy, dev portal sync, API publishing, Spectral linting) behave identically across legacy and new defaults — only the underlying providers change.

#### Migration 2 — Konnect provider `3.1.0` → `3.15`

- **Schema diffs.** `kong/konnect` 3.x has had multiple schema changes between minor versions. The PRD requires a documented diff covering every resource currently used (`konnect_team`, `konnect_team_role`, `konnect_control_plane`, system-account / vault module resources) with state migration steps.
- **State migration.** For each affected resource: required `terraform state mv` operations, attribute renames, and any provider-side data refresh. The migration must be re-runnable on a representative state file and produce a clean `plan` afterward.
- **Verification.** A clean `terraform plan` against a fresh local backend (MinIO) must show zero diffs after migration. This is the technical-success gate.
- **Rollback.** Documented downgrade path back to `3.1.0`, in case the migration surfaces an unforeseen issue mid-rollout. Pin lock-in (`= 3.15`) prevents accidental further drift.

### Implementation Considerations

- **Docs are part of MVP, not after.** A new top-level README, refreshed `make prepare` instructions, and per-action README parity ship in the same PR as the localization changes. Doc drift on a reference asset is silently corrosive.
- **`act` is the integration test.** Until end-to-end CI coverage is built, the `act`-runnable workflow set is the closest thing to a regression test suite. Every PR touching workflows or actions must show `act` runs in the description.
- **Documentation language.** All written content (README, action READMEs, comments, MIGRATION.md) is in English. Code identifiers follow the existing project conventions (kebab-case for actions/inputs, snake_case for Terraform).

## Product Scope

### MVP Strategy & Philosophy

**MVP approach: Problem-solving MVP.** The asset already exists and the federation pattern already works. The MVP unblocks the *SE demo motion* by removing third-party-infrastructure setup friction, modernizing a stale provider pin, and excising out-of-scope observability vendor references. New capability is explicitly excluded; functional parity with the current repo is the bar.

**Why this framing.** This isn't an "experience MVP" (we're not iterating on UX), a "platform MVP" (we're not building a new platform — Konnect is the platform), or a "revenue MVP" (no direct revenue path). It's a *problem-solving* MVP: the problem is "the SE can't reliably run this in front of a prospect," and the MVP solves exactly that, no more.

**Resource requirements.** Single platform engineer leading the refactor, with light SE input for end-to-end validation on a clean MacBook. The MVP is structured as independently-shippable PRs — partial completion remains usable, which is the appropriate hedge for a one-engineer effort.

### MVP Feature Set (Phase 1)

**Core user journeys supported:**
- Journey 1 — Sofia, SE first demo on a clean MacBook (happy path). The MVP must enable < 20-minute clone-to-first-dataplane.
- Journey 4 — Priya, API-team developer publishing an OpenAPI spec via existing companion repo. The MVP must preserve the Action contracts she depends on.

Journeys 2 (mid-demo provider swap) and 3 (Marcus's deep evaluation including backend swap) require Growth-scope pluggable backends and are not fully supported by the MVP.

**Must-have capabilities:**

1. **Localization — state backend.** MinIO via `docker-compose` replaces AWS S3 as the Terraform `backend "s3"` target in the default path. `scripts/create-s3-bucket.sh` works against MinIO.
2. **Localization — secrets backend connection.** HashiCorp Vault is retained as the sole secrets backend per Architecture ADR #001. Default path runs Vault as a local docker-compose dev container at `:8300` (rooted from `act.secrets`); production overrides `VAULT_ADDR` (and `VAULT_TOKEN`) to point at a real Vault cluster. Same module (`terraform/konnect-teams/modules/vault`), same provider, same paths — only the connection target changes.
3. **Localization — Kubernetes target.** OrbStack / Docker Desktop documented and validated as the `deploy-dp` default target. Helm `--set` flags / values adjusted for local clusters.
4. **Konnect Terraform provider bump 3.1.0 → 3.15.** State migration documented and verified (clean `plan` post-migration). Local source at `/Users/jordi.fernandez/github/terraform-provider-konnect` consulted for schema diffs.
5. **Observability vendor removal.** All references to Dynatrace and Datadog stripped from workflows, actions, charts, values files, and documentation.
6. **Action contract preservation.** Every Composite Action's input/output names and runtime behavior remain backwards-compatible with current consumers (including the existing companion API-team repo, which is updated separately). Any unavoidable breaking change is explicitly documented in `MIGRATION.md` with a remediation step for callers.
7. **Documentation refresh.** Top-level README rewritten for the local-first quickstart. Per-action README parity (every Composite Action gets the `provision-konnect-resources`-style README). `MIGRATION.md` covering legacy→local and provider 3.1.0→3.15.
8. **Best-practice improvements that preserve functionality.** Audited case-by-case during the refactor: `set -euo pipefail` consistency, action `name:` parity, dead-code removal, action input cleanup, redundant-step consolidation. No functional changes.

### Post-MVP Features (Phase 2 — Growth)

Capabilities that elevate the asset from "runs locally" to "demo-grade and adoption-ready":

- **Pluggable backend abstraction.** Single-configuration-knob swap for state (MinIO ↔ AWS S3), secrets (local docker-compose Vault ↔ remote HashiCorp Vault cluster via `VAULT_ADDR`, same provider per ADR #001), and Kubernetes (local ↔ cloud), with documented swap procedures. Unblocks Journeys 2 and 3.
- **Demo script + recorded walkthrough.** A 15–20 minute narrative walk-through of the federation seam, with both a written script (for SE study) and a recorded video (for async sharing).
- **Dev / staging / prod environment pattern.** Demonstrate environment promotion via the same Konnect-provider + Terraform pipeline, showing how the local-default model extends to production.

### Vision (Phase 3 — Future)

- **Workshop / enablement materials.** Slide deck and lab guide turning the repo into a customer workshop.
- **Multi-team / multi-portal showcase.** Several federated API teams running in parallel, illustrating richer-scale tenancy and shared platform services.
- **Optional integration demos.** Analytics, plugin patterns, custom dataplane configs — additive to the federation core, not part of it.
- **Kong-internal contribution flow.** SE feedback channel feeding improvements back into this repo, so the asset stays current as Konnect evolves.

### Explicitly Out of Scope

These items are *not* deferred — they are excluded from this PRD entirely:

- **New product features.** Any capability not already present in the current repo. The refactor is functional-parity-only.
- **Companion API-team reference repository updates.** The companion repo exists in a separate repository and will be aligned with this refactor on a separate work stream, after this PRD lands. This PRD's responsibility ends at preserving the Action contracts the companion repo consumes.
- **Observability integration.** Dynatrace/Datadog references are being removed; observability concerns belong in a separate repository and are outside this PRD's scope.
- **Comprehensive end-to-end CI test suite.** `act`-runnable workflows are the integration-test surface for this PRD. Building a fuller CI test harness is a separate initiative.
- **Per-runner Konnect resource namespacing.** Each SE has their own Konnect tenant, so cross-SE resource collisions are not a concern. The previously-considered `${USER}-` namespace prefix is dropped.

### Risk Mitigation Strategy

#### Technical Risks

- **Konnect provider 3.15 schema breakage may surface deep in the migration.**
  *Mitigation:* Validate `terraform plan` against the new provider for every module *first* — before proceeding with localization work. Use the local source at `/Users/jordi.fernandez/github/terraform-provider-konnect` to inspect schema diffs ahead of state migration. Document the migration incrementally rather than as a single big-bang.

- **MinIO S3-compatibility quirks for Terraform `backend "s3"`.**
  *Mitigation:* Land MinIO state-backend changes *first* in the MVP sequence — it's the most likely-to-surprise change. Validate end-to-end (init → plan → apply → state read) against MinIO before integrating downstream changes. Keep AWS S3 path manually verifiable as a fallback during the validation period.

- **Konnect Vault primitive coverage was a concern for matching the HashiCorp Vault patterns currently used** (per-team KV mounts, `system-accounts/sa-<team-name>` paths).
  *Resolved by Architecture ADR #001:* HashiCorp Vault is retained as the sole secrets backend; the local default runs Vault as a docker-compose dev container, production swaps `VAULT_ADDR` to a real Vault cluster. No primitive-coverage audit needed; no rewrite of `system-accounts/sa-<team-name>` paths required. Konnect Vault is out of scope.

- **Silent Action-contract drift during refactor breaks the existing companion API-team repo.**
  *Mitigation:* Capture a baseline of every Composite Action's input/output schema (and observable behavior) before refactor work begins. Diff against post-refactor schema before merging. Any unavoidable breaking change is explicitly documented in `MIGRATION.md` and called out in the PR description.

#### Adoption Risks

- **SEs may continue using pre-baked demos rather than adopting this.**
  *Mitigation:* Pair the refactor landing with an internal SE comms / demo session that visibly shows the time-to-first-dataplane improvement. Collect SE feedback as input for Growth-scope demo script work. Adoption is measured at 3 months and 6 months per Success Criteria.

- **Repo perceived as a Kong-internal experiment rather than a canonical asset.**
  *Mitigation:* Top-level README explicitly frames the repo as the canonical federated platform-ops reference. README links the existing companion API-team repo so the federation seam is visible to readers without running anything.

#### Resource Risks

- **Single-engineer effort; if pulled into other work mid-refactor, the repo could end up half-localized.**
  *Mitigation:* Structure MVP as **independently-shippable PRs** rather than a monolithic refactor — state backend, secrets backend, k8s target, provider bump, observability removal, docs each landable on their own. Partial completion still leaves the repo in a usable, documented state. Recommended landing sequence: provider bump → state backend → secrets backend → k8s target → observability removal → docs refresh.

- **Validation requires SE testing on a clean MacBook, which may slip if SEs are unavailable.**
  *Mitigation:* The owning engineer can perform first-pass validation on their own MacBook (representative MVP-environment); SE validation is the *acceptance* gate, not the *implementation* gate. SE-side testing can fold into the existing demo cycle rather than blocking on dedicated time.

## Functional Requirements

These functional requirements define the complete capability contract for `kw-platform-ops`. They span MVP and Growth scope per Step 8 (Project Scoping); phasing is documented in that section, not duplicated here. Vision-scope capabilities are intentionally not enumerated as FRs — they will be added in future PRD revisions.

### Local Bootstrap & Environment

- **FR1.** A Solutions Engineer can clone the repository to a clean macOS environment and bring the full local execution stack (state backend, Actions runner, helper services) to a runnable state via a single Make target.
- **FR2.** The repository provides an S3-compatible Terraform state backend that runs locally without requiring any cloud-infrastructure account.
- **FR3.** The repository provides a GitHub Actions runner environment compatible with executing every platform workflow via `act` on macOS, end-to-end, without manual hand-edits.
- **FR4.** The repository declares all required local dependencies (container runtime, `act`, Terraform, Helm, kubectl, decK, Spectral, etc.) and produces an actionable error message when any are missing or out-of-version.
- **FR5.** An operator can start, stop, and reset the local execution environment to a clean state via documented Make targets.
- **FR6.** An operator can configure the only required external credential — a Konnect access token — through a single gitignored local secrets file, without modifying any tracked source.

### Konnect Resource Provisioning

- **FR7.** An operator can provision Konnect teams from declarative YAML files committed to the repository.
- **FR8.** An operator can provision Konnect system accounts and persist their tokens to HashiCorp Vault (the sole secrets backend per Architecture ADR #001; local docker-compose Vault by default, real Vault cluster via `VAULT_ADDR` swap for production).
- **FR9.** An operator can provision Konnect control planes referenced by the team YAML resources.
- **FR10.** The provisioning pipeline validates every YAML resource definition against its schema before any infrastructure mutation is attempted.
- **FR11.** The provisioning pipeline rejects YAML resources that declare entitlements outside the documented supported set.
- **FR12.** An operator can re-run the provisioning pipeline idempotently — already-provisioned resources produce no diff and no infrastructure mutation.

### Dataplane Deployment

- **FR13.** An operator can deploy a Kong Gateway dataplane to a local Kubernetes cluster (OrbStack or Docker Desktop) via the `deploy-dp` Action.
- **FR14.** An operator can deploy a Kong Gateway dataplane to a cloud Kubernetes cluster via the same `deploy-dp` Action by changing only configuration inputs — no source code changes.
- **FR15.** An operator can specify the Kong Gateway image tag and the Helm chart version per `deploy-dp` invocation, with documented defaults.
- **FR16.** A deployed dataplane registers with the hosted Konnect control plane and reports a healthy status in Konnect's view of the dataplane.

### API Configuration Publishing

- **FR17.** An API-team workflow can lint an OpenAPI specification using the bundled Spectral OWASP ruleset and surface lint failures as PR-time GitHub check feedback.
- **FR18.** An API-team workflow can publish a linted OpenAPI specification to a Konnect-managed dev portal via decK in a single Action invocation.
- **FR19.** Re-running the publish workflow against an unchanged OpenAPI specification produces no observable change in Konnect (idempotent sync).
- **FR20.** Lint failures from the publishing pipeline include file, line, and rule context in the surfaced error — not raw log output.

### Developer Portal & Dashboards

- **FR21.** An operator can apply Konnect developer-portal configuration (`konnect/developer-portal/config.yaml`, `portal/*.yaml`) declaratively via the `developer-portal` workflow.
- **FR22.** An operator can apply Konnect dashboard configurations (`konnect/dashboards/`) declaratively, with pre-mutation validation.

### Operator Onboarding Webapp

- **FR23.** An operator can use the bundled Flask webapp (`webapp/onboard_team_app.py`) to author or edit a team YAML resource interactively, producing output that conforms to the YAML schema enforced by FR10.

### Action Contract Stability

- **FR24.** Every published Composite Action declares all inputs (with `description`, `required`, and `default` for optional inputs) and all outputs (with `description`) in its `action.yml`.
- **FR25.** Every published Composite Action ships a `README.md` documenting its inputs, outputs, side effects, an example caller workflow, and common failure modes — matching the structure of the `provision-konnect-resources` README.
- **FR26.** An API-team workflow can reference a published Composite Action by a version-pinned ref (tag or commit SHA) and receive stable input/output contract behavior at that ref.
- **FR27.** Breaking changes to any published Composite Action's input or output contract are documented in `MIGRATION.md` with a remediation step for callers.
- **FR28.** A reader can determine the full input/output contract of every published Composite Action by reading the repository alone, without running any workflow.

### Backend & Target Configuration

- **FR29.** An operator can select the Terraform state backend between local MinIO (default) and AWS S3 (alternative) via documented configuration, without modifying HCL source.
- **FR30.** An operator can select the HashiCorp Vault connection target between a local docker-compose dev Vault (default) and a real Vault cluster (alternative) by overriding `VAULT_ADDR` (and `VAULT_TOKEN`), without modifying Terraform module source. Konnect Vault is out of scope per Architecture ADR #001.
- **FR31.** An operator can select the Kubernetes deployment target between local clusters (OrbStack / Docker Desktop, default) and any cloud cluster (alternative) via the `deploy-dp` Action's documented inputs.

### Migration & Documentation

- **FR32.** The repository provides a `MIGRATION.md` documenting the migration path from the previous AWS-S3-and-HashiCorp-Vault setup to the new local-first defaults, including instructions for users who wish to retain a cloud-backed configuration.
- **FR33.** `MIGRATION.md` documents the Terraform state migration steps required when upgrading the Konnect provider from `3.1.0` to `3.15`, including any required `terraform state mv` operations and verification steps.
- **FR34.** The top-level `README.md` provides a quickstart that takes an SE from a fresh `git clone` to a successfully deployed dataplane, expressed as a sequential list of commands and expected outputs.

## Non-Functional Requirements

These NFRs specify HOW WELL the system must behave. They complement, but do not replace, the Functional Requirements.

### Performance

- **NFR1.** `make prepare` (cold clone → local execution stack ready) completes within **20 minutes** on a clean Apple Silicon MacBook with a typical home internet connection (≥ 50 Mbps).
- **NFR2.** `act`-driven execution of a typical platform workflow (e.g., `onboard-konnect-teams` against a single team, `deploy-dp` against a single dataplane) completes end-to-end within **5 minutes** from invocation.
- **NFR3.** The idle local Docker stack (MinIO + GitHub Actions runner + helper services) consumes ≤ 4 GB RAM and ≤ 4 vCPU on a 16 GB MacBook, leaving headroom for the operator's editor, browser, and a local Kubernetes cluster.

### Security

- **NFR4.** Secrets (`KONNECT_TOKEN`, system-account tokens, AWS keys when applicable, HashiCorp Vault tokens when applicable) are never emitted to workflow logs by any code path in this repository.
- **NFR5.** All local secret artifacts (`act.secrets`, `.tls/`, `.tmp/`, any vendor-specific credential files) are gitignored and excluded from container images. The `make clean` target removes them.
- **NFR6.** Secret material is supplied to Composite Actions via explicit inputs declared in the caller workflow; `secrets: inherit` is not used. Within an Action, secret material flows through `$GITHUB_ENV` only when downstream steps require env-style access, never via repository-wide environment variables.
- **NFR7.** The repository contains no real customer data, real customer names, real internal Kong URLs, or partner identifiers. All example resources reference the fictional `flight-operations` tenant or equivalent fictitious entities.
- **NFR8.** Third-party tooling versions used in the integration surface are exact-pinned where their schema is unstable across versions: `kong/konnect = 3.15` (Terraform provider), `decK v1.51.0`, `@stoplight/spectral-owasp-ruleset@^2.0`. Pin updates are explicit, reviewed changes — never "latest."
- **NFR9.** Konnect system-account tokens flow only through HashiCorp Vault (local docker-compose dev container by default, real Vault cluster as alternative — same provider per Architecture ADR #001). They are never exposed as Terraform outputs and never written to disk outside Vault's storage.

### Reliability & Compatibility

- **NFR10.** **100% of platform workflows** (`onboard-konnect-teams`, `developer-portal`, `deploy-dp`, `test-sync-api-configuration`, `publish-api-configuration`) run end-to-end via `act` on macOS without manual hand-edits.
- **NFR11.** The repository is verified to work on the latest two major macOS versions running on Apple Silicon. Intel Macs and Linux are not a tested support matrix; they may work but are not blocking.
- **NFR12.** Validation gates (YAML schema validation, Spectral OpenAPI lint, `terraform plan` consistency, schema-required field checks) cannot be bypassed via `continue-on-error: true`, `|| true`, or any equivalent pattern. Lint or plan failures cause workflow failure.
- **NFR13.** Error output from any validation, lint, or plan step includes sufficient context (file path, line number, rule ID or resource address) for an SE to identify the cause and apply a documented one-line fix without consulting external resources.

### Scalability

- **NFR14.** The local execution stack is sized for a single Solutions Engineer running a typical demo (one team, one dataplane, one OpenAPI specification). Multi-team, multi-portal, and multi-environment scenarios are Vision-scope and are not non-functional requirements for the current PRD.

### Integration & Extensibility

- **NFR15.** Pluggable backend swaps (Terraform state: MinIO ↔ AWS S3; secrets: local docker-compose Vault ↔ remote Vault cluster via `VAULT_ADDR` swap, same HashiCorp Vault provider per Architecture ADR #001; Kubernetes target: local ↔ cloud) are achievable by configuration changes alone — no source-code modifications, no Terraform module rewrites, no Action input renames. *(Growth-scope per Step 8.)*
- **NFR16.** Composite Action input and output contracts are stable across tagged releases. A consumer workflow pinned to a release tag observes identical contract surface for the lifetime of that tag. Breaking changes require a new tagged release with a documented `MIGRATION.md` entry.
- **NFR17.** The Konnect Terraform provider pin is exact (`= 3.15`); provider drift across environments is detectable by running `terraform init -upgrade` and observing diff output.

### Documentation Quality

- **NFR18.** Every published Composite Action's README is non-divergent from its `action.yml` at every release: every input declared in `action.yml` appears in the README's input table with matching name, type, required flag, and default; every output likewise. Drift is treated as a release-blocking defect.
- **NFR19.** The top-level `README.md` is readable cold (no prior context) in under 30 minutes by a reader unfamiliar with the repository, and conveys: (a) the federated platform-ops model and the seam between this repo and API-team repos, (b) the local-first quickstart from clone to first-dataplane, (c) the location of the companion API-team reference repository.
