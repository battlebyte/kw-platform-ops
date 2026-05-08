---
project_name: 'kw-platform-ops'
user_name: 'Jordi'
date: '2026-05-07'
stepsCompleted: ['step-01-document-discovery', 'step-02-prd-analysis', 'step-03-epic-coverage-validation', 'step-04-ux-alignment', 'step-05-epic-quality-review', 'step-06-final-assessment']
status: 'complete'
assessor: 'Claude (bmad-check-implementation-readiness)'
filesIncluded:
  prd: '_bmad-output/planning-artifacts/prd.md'
  architecture: '_bmad-output/planning-artifacts/architecture.md'
  epics: '_bmad-output/planning-artifacts/epics.md'
  ux: null
---

# Implementation Readiness Assessment Report

**Date:** 2026-05-07
**Project:** kw-platform-ops

## Document Inventory

| Type | Path | Size | Modified |
|------|------|------|----------|
| PRD | `_bmad-output/planning-artifacts/prd.md` | 53 KB | 2026-05-06 17:24 |
| Architecture | `_bmad-output/planning-artifacts/architecture.md` | 44 KB | 2026-05-06 19:55 |
| Epics & Stories | `_bmad-output/planning-artifacts/epics.md` | 67 KB | 2026-05-07 16:01 |
| UX Design | _not found_ | — | — |

**Notes:**
- No sharded versions present; no duplicates to resolve.
- Stories appear embedded within `epics.md` rather than as separate files.
- UX document missing — confirmed out of scope by user (platform-engineering repo, no UX surface).
- Stories will be validated as embedded sections in `epics.md` (confirmed by user).

## PRD Analysis

### Functional Requirements

**Local Bootstrap & Environment**
- **FR1.** A Solutions Engineer can clone the repository to a clean macOS environment and bring the full local execution stack (state backend, Actions runner, helper services) to a runnable state via a single Make target.
- **FR2.** The repository provides an S3-compatible Terraform state backend that runs locally without requiring any cloud-infrastructure account.
- **FR3.** The repository provides a GitHub Actions runner environment compatible with executing every platform workflow via `act` on macOS, end-to-end, without manual hand-edits.
- **FR4.** The repository declares all required local dependencies (container runtime, `act`, Terraform, Helm, kubectl, decK, Spectral, etc.) and produces an actionable error message when any are missing or out-of-version.
- **FR5.** An operator can start, stop, and reset the local execution environment to a clean state via documented Make targets.
- **FR6.** An operator can configure the only required external credential — a Konnect access token — through a single gitignored local secrets file, without modifying any tracked source.

**Konnect Resource Provisioning**
- **FR7.** An operator can provision Konnect teams from declarative YAML files committed to the repository.
- **FR8.** An operator can provision Konnect system accounts and persist their tokens to the configured secrets backend (Konnect Vault by default).
- **FR9.** An operator can provision Konnect control planes referenced by the team YAML resources.
- **FR10.** The provisioning pipeline validates every YAML resource definition against its schema before any infrastructure mutation is attempted.
- **FR11.** The provisioning pipeline rejects YAML resources that declare entitlements outside the documented supported set.
- **FR12.** An operator can re-run the provisioning pipeline idempotently — already-provisioned resources produce no diff and no infrastructure mutation.

**Dataplane Deployment**
- **FR13.** An operator can deploy a Kong Gateway dataplane to a local Kubernetes cluster (OrbStack or Docker Desktop) via the `deploy-dp` Action.
- **FR14.** An operator can deploy a Kong Gateway dataplane to a cloud Kubernetes cluster via the same `deploy-dp` Action by changing only configuration inputs — no source code changes.
- **FR15.** An operator can specify the Kong Gateway image tag and the Helm chart version per `deploy-dp` invocation, with documented defaults.
- **FR16.** A deployed dataplane registers with the hosted Konnect control plane and reports a healthy status in Konnect's view of the dataplane.

**API Configuration Publishing**
- **FR17.** An API-team workflow can lint an OpenAPI specification using the bundled Spectral OWASP ruleset and surface lint failures as PR-time GitHub check feedback.
- **FR18.** An API-team workflow can publish a linted OpenAPI specification to a Konnect-managed dev portal via decK in a single Action invocation.
- **FR19.** Re-running the publish workflow against an unchanged OpenAPI specification produces no observable change in Konnect (idempotent sync).
- **FR20.** Lint failures from the publishing pipeline include file, line, and rule context in the surfaced error — not raw log output.

**Developer Portal & Dashboards**
- **FR21.** An operator can apply Konnect developer-portal configuration (`konnect/developer-portal/config.yaml`, `portal/*.yaml`) declaratively via the `developer-portal` workflow.
- **FR22.** An operator can apply Konnect dashboard configurations (`konnect/dashboards/`) declaratively, with pre-mutation validation.

**Operator Onboarding Webapp**
- **FR23.** An operator can use the bundled Flask webapp (`webapp/onboard_team_app.py`) to author or edit a team YAML resource interactively, producing output that conforms to the YAML schema enforced by FR10.

**Action Contract Stability**
- **FR24.** Every published Composite Action declares all inputs (with `description`, `required`, and `default` for optional inputs) and all outputs (with `description`) in its `action.yml`.
- **FR25.** Every published Composite Action ships a `README.md` documenting its inputs, outputs, side effects, an example caller workflow, and common failure modes — matching the structure of the `provision-konnect-resources` README.
- **FR26.** An API-team workflow can reference a published Composite Action by a version-pinned ref (tag or commit SHA) and receive stable input/output contract behavior at that ref.
- **FR27.** Breaking changes to any published Composite Action's input or output contract are documented in `MIGRATION.md` with a remediation step for callers.
- **FR28.** A reader can determine the full input/output contract of every published Composite Action by reading the repository alone, without running any workflow.

**Backend & Target Configuration**
- **FR29.** An operator can select the Terraform state backend between local MinIO (default) and AWS S3 (alternative) via documented configuration, without modifying HCL source.
- **FR30.** An operator can select the secrets backend between Konnect Vault (default) and HashiCorp Vault (alternative) via documented configuration, without modifying Terraform module source.
- **FR31.** An operator can select the Kubernetes deployment target between local clusters (OrbStack / Docker Desktop, default) and any cloud cluster (alternative) via the `deploy-dp` Action's documented inputs.

**Migration & Documentation**
- **FR32.** The repository provides a `MIGRATION.md` documenting the migration path from the previous AWS-S3-and-HashiCorp-Vault setup to the new local-first defaults, including instructions for users who wish to retain a cloud-backed configuration.
- **FR33.** `MIGRATION.md` documents the Terraform state migration steps required when upgrading the Konnect provider from `3.1.0` to `3.15`, including any required `terraform state mv` operations and verification steps.
- **FR34.** The top-level `README.md` provides a quickstart that takes an SE from a fresh `git clone` to a successfully deployed dataplane, expressed as a sequential list of commands and expected outputs.

**Total FRs:** 34

### Non-Functional Requirements

**Performance**
- **NFR1.** `make prepare` (cold clone → local execution stack ready) completes within 20 minutes on a clean Apple Silicon MacBook with a typical home internet connection (≥ 50 Mbps).
- **NFR2.** `act`-driven execution of a typical platform workflow completes end-to-end within 5 minutes from invocation.
- **NFR3.** The idle local Docker stack consumes ≤ 4 GB RAM and ≤ 4 vCPU on a 16 GB MacBook.

**Security**
- **NFR4.** Secrets are never emitted to workflow logs by any code path.
- **NFR5.** All local secret artifacts (`act.secrets`, `.tls/`, `.tmp/`, vendor-specific credential files) are gitignored; `make clean` removes them.
- **NFR6.** Secret material is supplied to Composite Actions via explicit inputs declared in the caller workflow; `secrets: inherit` is not used. Within an Action, secrets flow through `$GITHUB_ENV` only when needed.
- **NFR7.** The repository contains no real customer data, names, internal Kong URLs, or partner identifiers — only fictional `flight-operations` or equivalent.
- **NFR8.** Third-party tooling versions are exact-pinned where schema is unstable: `kong/konnect = 3.15`, `decK v1.51.0`, `@stoplight/spectral-owasp-ruleset@^2.0`. No "latest."
- **NFR9.** Konnect system-account tokens flow only through the configured secrets backend; never as Terraform outputs, never to disk outside that backend.

**Reliability & Compatibility**
- **NFR10.** 100% of platform workflows (`onboard-konnect-teams`, `developer-portal`, `deploy-dp`, `test-sync-api-configuration`, `publish-api-configuration`) run end-to-end via `act` on macOS without hand-edits.
- **NFR11.** Verified on latest two major macOS versions on Apple Silicon. Intel/Linux not tested.
- **NFR12.** Validation gates (YAML schema, Spectral lint, `terraform plan`, schema field checks) cannot be bypassed via `continue-on-error: true` or `|| true`.
- **NFR13.** Error output from validation/lint/plan steps includes file path, line number, rule ID or resource address.

**Scalability**
- **NFR14.** Local stack sized for one SE running a typical demo (1 team, 1 dataplane, 1 spec). Multi-team/portal/env scenarios are Vision-scope.

**Integration & Extensibility**
- **NFR15.** Pluggable backend swaps (state: MinIO ↔ S3; secrets: Konnect Vault ↔ HashiCorp Vault; K8s: local ↔ cloud) by configuration alone — no source changes. *(Growth-scope.)*
- **NFR16.** Composite Action input/output contracts stable across tagged releases; breaking changes require new tag + `MIGRATION.md` entry.
- **NFR17.** Konnect Terraform provider pin is exact (`= 3.15`); drift detectable via `terraform init -upgrade`.

**Documentation Quality**
- **NFR18.** Every published Composite Action's README is non-divergent from its `action.yml` at every release; drift is release-blocking.
- **NFR19.** Top-level `README.md` readable cold in under 30 minutes; conveys (a) federated platform-ops model + seam, (b) local-first quickstart, (c) companion API-team repo location.

**Total NFRs:** 19

### Additional Requirements & Constraints

**MVP scope (Phase 1) must-have capabilities** (from §Product Scope):
1. Localization — state backend (MinIO replaces AWS S3 in default path).
2. Localization — secrets backend (Konnect Vault replaces HashiCorp Vault in default path).
3. Localization — Kubernetes target (OrbStack / Docker Desktop default for `deploy-dp`).
4. Konnect Terraform provider bump 3.1.0 → 3.15 with documented state migration.
5. Observability vendor removal (Dynatrace + Datadog stripped from workflows, actions, charts, values, docs).
6. Action contract preservation (no breaking changes to consumers; any unavoidable break documented in `MIGRATION.md`).
7. Documentation refresh (README rewrite; per-action README parity; `MIGRATION.md`).
8. Best-practice improvements that preserve functionality (audited case-by-case).

**Growth scope (Phase 2)** — explicitly Phase 2: pluggable backend abstraction with single-knob swap (this is the source of FR29, FR30, FR31, NFR15).

**Recommended landing sequence** (from §Risk Mitigation): provider bump → state backend → secrets backend → k8s target → observability removal → docs refresh.

**Explicitly Out of Scope:**
- New product features (parity-only refactor).
- Companion API-team reference repository updates (separate work stream).
- Observability integration (Dynatrace/Datadog being removed).
- Comprehensive end-to-end CI test suite (`act` is the integration surface).
- Per-runner Konnect resource namespacing (`${USER}-` prefix dropped).

**Technical-success gates** (from §Success Criteria → Technical Success):
- Zero hard dependency on third-party cloud in default path.
- Konnect Terraform provider on `kong/konnect = 3.15` with clean plan/apply.
- 100% pass rate of platform workflows under `act` on macOS.
- Konnect Vault default; HashiCorp Vault swappable.
- MinIO default; AWS S3 swappable.
- Local Kubernetes default; cloud K8s swappable.
- Dynatrace/Datadog references fully removed.
- Functional parity with current behavior preserved.

### PRD Completeness Assessment

**Strengths:**
- 34 FRs and 19 NFRs are explicitly numbered, well-scoped, and individually testable.
- Phasing (MVP vs. Growth) is documented; FR29–FR31 + NFR15 are flagged as Growth-scope.
- Out-of-scope items are explicit, not implicit — reduces interpretation risk.
- Success criteria include measurable outcomes (timings, percentages, version pins).
- Risk mitigation includes a concrete recommended landing sequence.

**Initial concerns to validate against epics:**
- Phasing is encoded inline in §Product Scope but not on each FR — coverage validation must verify epics correctly classify Phase 1 vs Phase 2 work, especially around FR29/FR30/FR31 (pluggable swaps) and NFR15.
- "Best-practice improvements" (MVP item 8) is a category, not a discrete capability — needs epic decomposition to be tractable.
- FR23 (Flask onboarding webapp) is essentially a pre-existing capability that must remain working; epic coverage may legitimately be "no-op / preserve" rather than active work.
- "Functional parity" is asserted but not enumerated as discrete acceptance items — epic stories must capture parity verification, not just new behavior.
- Companion API-team repo is referenced (FR17 surfaces, FR25 example callers, NFR19 README link) but is out-of-scope for this PRD; coverage validation must not flag missing companion-repo work as a gap.

## Epic Coverage Validation

### Epic Inventory

| Epic | Title | Stories | Claimed FRs |
|------|-------|---------|-------------|
| 1 | Konnect Provider Modernization (3.1.0 → 3.15) | 6 | FR7, FR8, FR9, FR10, FR11, FR12, FR21, FR22, FR33 |
| 2 | Local-First Demo Bootstrap | 6 | FR1, FR2, FR3, FR4, FR5, FR6, FR29, FR30 |
| 3 | Pluggable Kubernetes Target | 3 | FR13, FR14, FR15, FR16, FR31 |
| 4 | API Publishing & Action Contract Stability | 5 | FR17, FR18, FR19, FR20, FR24, FR25, FR27, FR28 |
| 5 | Documentation Synthesis, Migration Path & Vendor Cleanup | 4+ | FR23, FR32, FR34 |

Total stories: 24+ (Epic 5 last story spans cutoff but is present per outline).

### FR Coverage Matrix

Legend: ✅ covered (FR map + story AC); ⚠️ covered by FR map but story AC is implicit/indirect; ❌ missing; ➖ deferred (out of MVP scope).

| FR | PRD Requirement (abridged) | Epic | Story Reference | Status |
|----|----------------------------|------|-----------------|--------|
| FR1 | Single-Make-target local stack bootstrap | 2 | 2.6 | ✅ |
| FR2 | S3-compatible local Terraform state backend | 2 | 2.1, 2.6 | ✅ |
| FR3 | `act`-runnable workflows on macOS | 2 | 2.3, 2.6 | ✅ |
| FR4 | Dependency self-discovery with actionable errors | 2 | 2.6 | ⚠️ See Gap #1 |
| FR5 | Start/stop/reset local stack via Make | 2 | 2.6 | ⚠️ See Gap #2 |
| FR6 | Single-credential bootstrap via gitignored file | 2 | 2.5 | ✅ |
| FR7 | Provision Konnect teams from YAML | 1 | 1.6 (verification) | ⚠️ See Gap #3 |
| FR8 | Provision system accounts to secrets backend | 1 | 1.3, 1.6 | ⚠️ See Gap #3 |
| FR9 | Provision Konnect control planes | 1 | 1.3 | ⚠️ See Gap #3 |
| FR10 | YAML schema validation pre-mutation | 1 | 1.6 (verification) | ⚠️ See Gap #3 |
| FR11 | Reject unsupported entitlements | 1 | (implicit in 1.6) | ⚠️ See Gap #3 |
| FR12 | Idempotent re-provisioning | 1 | 1.4 (state-mig idempotency) + 1.6 | ⚠️ See Gap #3 |
| FR13 | Deploy DP to local K8s | 3 | 3.2 | ✅ |
| FR14 | Deploy DP to cloud K8s via same Action | 3 | 3.3 | ✅ |
| FR15 | Configurable image tag + chart version | 3 | 3.1, 3.2 | ✅ |
| FR16 | DP registers healthy in Konnect | 3 | 3.2, 3.3 | ✅ |
| FR17 | Spectral OWASP lint w/ PR-time feedback | 4 | 4.5 | ✅ |
| FR18 | decK publish to Konnect dev portal | 4 | 4.5 | ✅ |
| FR19 | Idempotent re-publish | 4 | 4.5 | ✅ |
| FR20 | Lint failures include file/line/rule context | 4 | 4.5 | ✅ |
| FR21 | Apply dev-portal config declaratively | 1 | (implicit in 1.3, 1.6) | ⚠️ See Gap #4 |
| FR22 | Apply dashboard config with pre-mutation validation | 1 | (implicit in 1.3, 1.6) | ⚠️ See Gap #4 |
| FR23 | Flask webapp produces schema-conformant team YAML | 5 | 5.4 | ✅ |
| FR24 | Composite Actions declare all inputs/outputs | 4 | 4.1 | ✅ |
| FR25 | Per-action README parity (P4 structure) | 4 | 4.2 | ✅ |
| FR26 | Pin-to-tag stable contract behavior | — | — | ➖ Deferred to Growth phase per Architecture D4 (explicit in epics §Out of MVP scope). Defensible scoping. |
| FR27 | Breaking-change docs in `MIGRATION.md` | 4 | 4.3 (failure-msg reminder), 5.2 (slot reserved) | ⚠️ See Gap #5 |
| FR28 | Action contracts readable from repo without running | 4 | 4.1 + 4.2 | ✅ |
| FR29 | State backend selection MinIO ↔ S3 by config | 2 | 2.1, 2.3 | ✅ |
| FR30 | Secrets backend selection (reframed by ADR #001) | 2 | 2.5 (local default), 5.2 (swap docs) | ⚠️ See Gap #6 |
| FR31 | K8s target selection by config | 3 | 3.1, 3.2, 3.3 | ✅ |
| FR32 | `MIGRATION.md` legacy → local-first | 5 | 5.2 | ✅ |
| FR33 | `MIGRATION.md` Konnect provider 3.1.0 → 3.15 | 1 | 1.6 | ✅ |
| FR34 | Top-level README local-first quickstart | 5 | 5.3 | ✅ |

### NFR Coverage Matrix

| NFR | Requirement (abridged) | Story Reference | Status |
|-----|------------------------|-----------------|--------|
| NFR1 | `make prepare` < 20 min | 2.6 | ✅ |
| NFR2 | Workflow ≤ 5 min via `act` | 2.6, 3.2, 4.5 | ✅ |
| NFR3 | ≤ 4 GB RAM / ≤ 4 vCPU idle | 2.6 | ✅ |
| NFR4 | No secrets in logs | 2.6, 3.1, 3.2, 3.3, 4.5 | ✅ |
| NFR5 | Local secret artifacts gitignored; `make clean` removes | 2.5, 2.6 | ⚠️ See Gap #7 |
| NFR6 | No `secrets: inherit`; explicit input passing | — | ⚠️ See Gap #8 |
| NFR7 | No real customer/partner data | 5.3 (README check), 5.1 (vendor strip) | ⚠️ See Gap #9 |
| NFR8 | Exact pins for unstable schemas | 1.2 (Konnect 3.15) | ⚠️ See Gap #10 |
| NFR9 | System-account tokens flow only via secrets backend | (implicit in Epic 1) | ⚠️ See Gap #11 |
| NFR10 | 100% of platform workflows runnable via `act` | 2.6 (onboard), 3.2 (deploy-dp), 4.5 (publish) | ⚠️ See Gap #12 |
| NFR11 | Latest two macOS majors on Apple Silicon | — | ⚠️ See Gap #13 |
| NFR12 | No bypass on validation/lint/plan gates | 4.4 | ✅ |
| NFR13 | Errors include file/line/rule-ID context | 4.5 | ⚠️ See Gap #14 |
| NFR14 | Single-SE typical demo sizing | (scope statement) | ✅ |
| NFR15 | Pluggable backend swaps by config alone | 2.1+2.3 (state), 3.1 (k8s), 5.2 (vault swap docs) | ✅ |
| NFR16 | Action contract stability across tagged releases | — | ➖ Deferred with FR26 (out of MVP scope) |
| NFR17 | Exact Konnect pin; drift detectable | 1.2, 1.3 | ⚠️ See Gap #15 |
| NFR18 | README ↔ `action.yml` non-divergence at every release | 4.3 | ✅ |
| NFR19 | README cold-readable in < 30 min | 5.3 | ✅ |

### Coverage Statistics

- **Total PRD FRs:** 34
- **FRs with explicit story coverage:** 21 (62%)
- **FRs with implicit/indirect coverage flagged for review:** 12 (35%) — see Gaps below
- **FRs deferred out of MVP (defensible):** 1 (FR26, 3%)
- **FRs missing entirely:** 0
- **Total PRD NFRs:** 19
- **NFRs with explicit story coverage:** 9 (47%)
- **NFRs with implicit/indirect coverage flagged for review:** 9 (47%) — see Gaps below
- **NFRs deferred out of MVP:** 1 (NFR16)
- **NFRs missing entirely:** 0

**Headline:** No FR or NFR is *unaccounted for* in the FR Coverage Map. However, several have implicit/indirect coverage where the story acceptance criteria don't make the requirement individually testable. These are listed below as gaps to triage — not all need new stories; some are legitimate "verified by Epic 1's clean-plan gate" passive coverage given the parity-only refactor framing.

### Gap Analysis (Coverage Concerns)

#### Gap #1 — FR4: `scripts/check-deps.sh` referenced as a precondition, not delivered
- **Concern:** The FR Coverage Map credits Epic 2 with "Dependency self-discovery (`scripts/check-deps.sh`)", and Story 2.6's AC mentions `check-deps.sh` confirming dependencies. But no story explicitly **creates** `check-deps.sh`. Story 2.6 reads the script's existence as given.
- **Impact:** Implementation team may discover at validation time that the script doesn't exist or doesn't cover all required tools (Docker, `act`, `gh`, `terraform`, `helm`, `kubectl`).
- **Recommendation:** Add an explicit AC to Story 2.6 (or a new sub-story) authoring `scripts/check-deps.sh` with the dependency list and actionable error messages.

#### Gap #2 — FR5: "start, stop, reset" not all mapped to ACs
- **Concern:** Story 2.6 covers `make clean`/`make down` (stop + cleanup) and `make prepare` (start). "Reset to clean state" is implicit — no AC enumerates the full lifecycle (start → stop → reset → re-prep cycle).
- **Impact:** If `make clean` doesn't fully reset state (e.g., leaves the MinIO bucket populated, leaves Vault dev container with prior secrets), subsequent re-preps may behave non-deterministically.
- **Recommendation:** Either add an explicit "reset" AC to Story 2.6 (or confirm `make clean` + `make prepare` is the intended reset semantics; document accordingly).

#### Gap #3 — FR7–FR12: Konnect provisioning capabilities verified only as side effects of provider migration
- **Concern:** Epic 1 stories focus on the provider bump and state migration. FR7–FR12 (the actual capabilities — team provisioning, system accounts, control planes, validation gates, idempotency) are verified implicitly by Story 1.6's "apply canonical fixtures and observe zero diffs." There are no discrete ACs proving each capability functions end-to-end on the new provider.
- **Impact:** A schema diff that breaks (say) entitlements rejection (FR11) or idempotency (FR12) might pass Story 1.6's plan-zero-diff check while still being broken at runtime.
- **Recommendation:** Add ACs to Story 1.6 (or extend Story 2.6) that exercise each FR7–FR12 capability against the migrated provider:
  - Provision a fresh team end-to-end (FR7).
  - Verify system-account token lands in Vault path (FR8).
  - Apply with an unsupported entitlement and confirm rejection (FR11).
  - Re-run apply on unchanged input and confirm zero diff (FR12 idempotency).
- This aligns with the PRD's "functional parity" mandate as an acceptance gate.

#### Gap #4 — FR21, FR22: Developer portal & dashboards covered only narratively
- **Concern:** Story 1.3's narrative mentions "developer-portal and dashboard provisioning preserved" and ACs reference `portal_*` / `dashboard_*` submodules under `provision-konnect-resources/terraform/modules/`. But no AC exercises the `developer-portal` workflow end-to-end against MinIO or validates `konnect/dashboards/` pre-mutation validation.
- **Impact:** Same as Gap #3 — verification at provider-migration time may not catch downstream behavior regressions.
- **Recommendation:** Add an AC under Story 1.6 or a new Epic 1 story executing `developer-portal` workflow via `act` against MinIO + the `flight-operations` portal fixture. Same for at least one dashboard config.

#### Gap #5 — FR27: Breaking-change docs slot exists, but no story validates the policy
- **Concern:** Stories 4.3 and 5.2 reserve a slot in `MIGRATION.md` for action contract breaking changes, but no story asserts the policy works end-to-end (e.g., a "breaking change happens → MIGRATION.md is updated → reviewers can find it" path).
- **Impact:** If MVP introduces no breaking changes, this is fine. If any unavoidable breaking change surfaces during refactor, the policy may not be triggered.
- **Recommendation:** Acceptable for MVP. Document explicitly in PR template / contributing guide that breaking input/output changes require a `MIGRATION.md` entry. Lower priority.

#### Gap #6 — FR30: Secrets backend "selection" reframed by ADR #001 — verify reframe is acceptable
- **Concern:** PRD FR30 originally specified "selection between Konnect Vault (default) and HashiCorp Vault (alternative)." Architecture ADR #001 reframes this as: HashiCorp Vault is retained as the *sole* backend, with selection collapsed to a `VAULT_ADDR` env-var swap (local docker-compose Vault vs. real Vault cluster). Konnect Vault is explicitly out of scope.
- **Impact:** This is a meaningful PRD deviation. The PRD's Technical Success criteria stated "Konnect Vault replaces HashiCorp Vault as the secrets backend in the default path" — which the ADR reverses. The Risk Mitigation section flagged this exact concern ("Konnect Vault primitive coverage may not match the HashiCorp Vault patterns currently used") and authorized scope-narrowing. So the reframe is consistent with risk-mitigation guidance, but should be explicitly acknowledged.
- **Recommendation:** **Confirm with stakeholders** that the PRD-vs-ADR-vs-Epic alignment is intentional. If yes, update the PRD's FR30 + Technical Success bullet to match ADR #001 wording so future readers don't see a contradiction. If no, scope expansion is needed.

#### Gap #7 — NFR5: `make clean` removal of all artifacts not exhaustively tested
- **Concern:** Story 2.5 covers `act.secrets`/`act.secrets.example` gitignoring. Story 2.6 mentions `make clean` removes `.tls/`, `.tmp/` and "the working tree is clean." But not exhaustively verified that *every* secret artifact (per NFR5: `act.secrets`, `.tls/`, `.tmp/`, "vendor-specific credential files") is removed. "Vendor-specific credential files" is unspecified.
- **Impact:** Low — most artifacts are listed; the catch-all phrase is unactionable as written.
- **Recommendation:** Either narrow the NFR wording, or add an AC enumerating exactly which paths `make clean` purges.

#### Gap #8 — NFR6: `secrets: inherit` prohibition not mechanically enforced
- **Concern:** No story enforces that workflows pass secrets explicitly (vs. using `secrets: inherit`). This is a project-context.md rule, but no lint/grep gate enforces it. The lint workflows in Epic 4 cover bypass patterns and contract drift — not secret-passing patterns.
- **Impact:** A future contributor may use `secrets: inherit` and silently violate NFR6.
- **Recommendation:** Optional — add a lint pattern (in Story 4.4 or a new lint workflow) detecting `secrets: inherit` in callers of `.github/actions/*`. If not added, accept as a code-review-enforced rule and document in CONTRIBUTING.md.

#### Gap #9 — NFR7: No real customer data — README scrub only; broader repo not scrubbed
- **Concern:** Story 5.3 verifies the README has no real customer/partner identifiers. Story 5.1 strips Datadog/Dynatrace. But no story scans the full repo (workflows, actions, scripts, terraform, fixtures) for non-fictional identifiers.
- **Impact:** A `kong-customer-X` or real URL hiding in a YAML file or comment may slip through.
- **Recommendation:** Optional — add a one-off scan AC to a docs/cleanup story (e.g., `git grep -i` for known partner names + non-`flight-operations` tenant names). Low priority for MVP.

#### Gap #10 — NFR8: Pin verification only for `kong/konnect`; decK and Spectral not exercised
- **Concern:** Story 1.2 verifies the Konnect provider pin to `3.15`. No story explicitly verifies `decK v1.51.0` or `@stoplight/spectral-owasp-ruleset@^2.0` pins are still respected post-refactor.
- **Impact:** If a refactor accidentally bumps decK or the Spectral ruleset, NFR8 is silently violated.
- **Recommendation:** Story 4.5 already exercises Spectral and decK. Add an AC asserting the pins specifically (e.g., `grep "v1.51.0"` in the action `action.yml` and `package.json` for the Spectral ruleset version).

#### Gap #11 — NFR9: System-account tokens never as Terraform outputs — not story-tested
- **Concern:** This is a security guarantee. No story has an AC asserting `terraform output` does not expose system-account tokens.
- **Impact:** A schema change in the new provider could inadvertently expose tokens via outputs.
- **Recommendation:** Add an AC to Story 1.2 or 1.3: `terraform output -json | jq` shows no token-bearing field for system-account resources.

#### Gap #12 — NFR10: 100% of platform workflows via `act` — only 3 of 5 explicitly verified
- **Concern:** The PRD explicitly enumerates 5 platform workflows: `onboard-konnect-teams`, `developer-portal`, `deploy-dp`, `test-sync-api-configuration`, `publish-api-configuration`. Stories cover `onboard-konnect-teams` (2.6), `deploy-dp` (3.2), `publish-api-configuration` (4.5). **`developer-portal` and `test-sync-api-configuration` are not covered by an explicit `act` verification story.**
- **Impact:** NFR10's "100%" is not achievable on current epic scope. This is the most concrete coverage gap.
- **Recommendation:** Add an explicit AC (extend Story 2.6 or 1.6, or create a new story) running `developer-portal` and `test-sync-api-configuration` workflows via `act` against MinIO + Vault dev container, with a passing happy-path acceptance.

#### Gap #13 — NFR11: macOS support matrix not story-tested
- **Concern:** "Latest two major macOS versions on Apple Silicon" is not asserted as an AC anywhere. Story 2.6 says "clean Apple Silicon macOS machine" but doesn't pin a version.
- **Impact:** Low — practically tested as a side effect of the engineer's own MacBook environment. Multi-version testing is unrealistic for a single-engineer effort.
- **Recommendation:** Either narrow NFR11 to a single tested macOS version (the engineer's), or accept as a "best-effort" claim with no formal verification gate. Update PRD to match reality.

#### Gap #14 — NFR13: Error context only verified for Spectral; not for YAML validator or Terraform plan
- **Concern:** Story 4.5 verifies Spectral lint failures include file/line/rule. NFR13 covers all validation, lint, *and plan* steps. No story asserts YAML validator output or `terraform plan` output is similarly contextual.
- **Impact:** Low — these tools naturally emit context; risk is regression in output formatting.
- **Recommendation:** Optional — add a sample-failure AC to Story 1.6 (terraform plan with deliberate breakage) or Story 2.6 (YAML validator with deliberate breakage), asserting actionable error context.

#### Gap #15 — NFR17: Drift detection via `terraform init -upgrade` not exercised
- **Concern:** NFR17 says drift is "detectable by running `terraform init -upgrade` and observing diff output." No story exercises this drift-detection mechanic.
- **Impact:** Low — this is a passive mechanic of Terraform itself with an exact pin.
- **Recommendation:** Acceptable as passive verification. Optionally add as a one-line check in Story 1.2.

### Critical vs. Low-Priority Gap Summary

**Must-fix before implementation:**
- **Gap #6** (FR30 / ADR #001 reframing) — confirm scope deviation is intentional and update PRD wording for consistency. PRD↔Architecture↔Epics misalignment is the highest-risk gap because it changes the intended Technical Success criteria.
- **Gap #12** (NFR10 — `developer-portal` + `test-sync-api-configuration` not act-verified) — concrete coverage gap of explicit PRD-listed workflows.
- **Gap #1** (FR4 — `check-deps.sh` not authored by any story) — implementation precondition that's referenced but not delivered.

**Should-fix for parity verification:**
- **Gap #3** (FR7–FR12 verified only via plan-zero-diff) — add capability-specific ACs to make parity verification explicit.
- **Gap #4** (FR21, FR22 — portal/dashboards) — same parity-verification concern.

**Nice-to-have / defensible-as-is:**
- Gaps #2, #5, #7–#11, #13–#15 — most are testable side effects of existing stories or reasonable scope decisions.

## UX Alignment Assessment

### UX Document Status

**Not Found** — confirmed out of scope by user. No UX/UI specification document exists; none required.

### Rationale

`kw-platform-ops` is a platform-engineering reference repository. Its primary surfaces are:
- GitHub Actions / Workflows (CLI invocations and YAML configuration — no GUI).
- Terraform / Helm / shell scripts (operator-side tooling).
- A thin Flask onboarding webapp (`webapp/onboard_team_app.py`) intentionally kept lightweight per project-context.md ("keep business logic in shell scripts / Terraform — do not migrate Konnect logic into Python").

The PRD does not reference UI/UX in any FR or NFR. The four user journeys describe terminal-driven and IDE-driven flows, not graphical experiences. The epics document at line 18 explicitly notes: "No UX Design document exists for this project — `kw-platform-ops` is a platform-engineering reference repository with no significant UI surface."

### UI-Adjacent Considerations Already Addressed

Although no formal UX doc exists, several near-UX concerns appear in PRD/Epics and are appropriately scoped:

| Concern | Where addressed | Status |
|---------|-----------------|--------|
| Terminal output quality (`make prepare` walkthrough readability) | PRD §Code Examples ("stdout is curated to read as a guided walkthrough"); Story 2.5 mentions "terminal-friendly message" | ✅ Acknowledged |
| Error message quality (file/line/rule context) | NFR13; Story 4.5 (Spectral); Gap #14 above flags broader coverage | ⚠️ Partially covered |
| README cold-readability ("UX of docs") | NFR19; Story 5.3 | ✅ Covered |
| Action input names as developer UX (kebab-case, descriptive) | FR24, FR28; Story 4.1 | ✅ Covered |
| Flask webapp interaction quality | FR23; Story 5.4 (form fields, schema-conforming output) | ✅ Covered |
| GitHub PR check display (Spectral lint feedback as "PR-time UX") | FR17, FR20; Story 4.5 | ✅ Covered |

These are best understood as **developer-experience (DX)** concerns rather than end-user UX, and are correctly handled within their respective FRs/stories without needing a separate UX artifact.

### Alignment Issues

**None identified.** PRD and Architecture both consistently treat the project as a non-UI reference implementation. Epics document opens with an explicit acknowledgement that no UX spec exists. There is no implicit UI surface that would warrant a missing-UX warning.

### Warnings

**None.** The absence of a UX document is intentional and consistent across all three planning artifacts.

## Epic Quality Review

Validation against `bmad-create-epics-and-stories` standards: user-value focus, epic independence, story sizing, dependency analysis, AC quality. Project is **brownfield**, so greenfield-specific checks (starter template, initial-project-setup story) are not applied; brownfield migration/integration patterns are evaluated instead.

### Epic Structure Validation

| Epic | User-Value Focus | Independence | Brownfield-Appropriate | Verdict |
|------|------------------|--------------|------------------------|---------|
| 1. Konnect Provider Modernization | ⚠️ Title is technical, but value = "platform unblocks subsequent demo work on a stale provider"; PRD risk-mitigation explicitly endorses this as the first independently-shippable PR | ✅ Self-contained: own MIGRATION.md §2, own clean-plan gate | ✅ Modernization is a brownfield-native pattern | ✅ Defensible |
| 2. Local-First Demo Bootstrap | ✅ Sofia (SE) clones-and-runs in < 20 min — strong user value | ✅ Depends on Epic 1 only (acceptable per "Epic N can use 1..N-1 outputs") | ✅ Brownfield bootstrap | ✅ Strong |
| 3. Pluggable Kubernetes Target | ✅ Operator can target local or cloud K8s | ✅ Additive, non-breaking; can land any time after Epic 2 | ✅ | ✅ Strong |
| 4. API Publishing & Action Contract Stability | ✅ API-team developers get clear contracts + PR feedback | ✅ Can land in parallel with Epic 3 | ✅ | ✅ Strong |
| 5. Documentation Synthesis, Migration Path & Vendor Cleanup | ✅ Marcus reads README cold and groks the federation seam | ✅ Lands last by design (synthesis depends on prior epic outputs) | ✅ | ✅ Strong |

**Epic-title note:** Epics 1 and 5 have technical-leaning titles ("Modernization", "Documentation Synthesis"). In a parity-only brownfield refactor, fully user-centric titles would feel forced. The epic *goals* are user-anchored, which is what matters.

**No critical structural violations.** No epic delivers zero user value, none has forward dependencies on later epics, and the sequencing/independence claims in epics §Sequencing & Dependencies hold under inspection.

### Story Quality Assessment

#### Per-epic story summary

| Epic | # Stories | AC quality | Sizing | Issues |
|------|-----------|-----------|--------|--------|
| 1 | 6 | Detailed, BDD-format, specific | Mixed (1.1 produces a document; 1.6 bundles verification + docs) | See findings #1, #2 |
| 2 | 6 | Detailed, BDD-format, specific | Right-sized | See finding #3 |
| 3 | 3 | Detailed, BDD-format, specific | Right-sized | None |
| 4 | 5 | Detailed, BDD-format, specific | Right-sized | See finding #4 |
| 5 | 4+ | Detailed, BDD-format, specific (story 5.4 cuts off in current artifact) | Right-sized | See finding #5 |

#### AC Quality Spot-Check

Sampled BDD acceptance criteria from each epic. Common strengths:
- Given/When/Then format applied consistently.
- Specific numerical thresholds (NFR1 < 20 min, NFR3 ≤ 4 GB / 4 vCPU, NFR2 ≤ 5 min) appear as testable ACs.
- Negative-path ACs present (e.g., Story 4.5: "deliberately malformed OpenAPI spec" → workflow fails, decK does not run).
- Idempotency assertions (Stories 1.4, 1.5, 2.4, 4.5).
- Security ACs (e.g., "no portion of the cloud kubeconfig content appears in logs" — NFR4 verification in Story 3.3).

No vague ACs (e.g., "user can login") observed. ACs are individually testable.

### Dependency Analysis

#### Within-Epic Dependency Graph (high-level)

- **Epic 1:** 1.1 → {1.2, 1.3} → 1.4 → 1.5 → 1.6. Linear, no backward references. ✅
- **Epic 2:** {2.1, 2.2, 2.4, 2.5} → 2.3 → 2.6. **Issue:** Story 2.3 AC #4 explicitly references "create-state-bucket.sh (delivered in Story 2.4)" — forward reference. See Finding #3.
- **Epic 3:** 3.1 → {3.2, 3.3}. ✅
- **Epic 4:** {4.1, 4.2} → 4.3; 4.4 standalone; 4.5 standalone. AC in 4.3 acknowledges the 4.1+4.2 prerequisite explicitly. ✅
- **Epic 5:** 5.1 standalone; 5.2 standalone; 5.3 references 5.2 + 5.4 (forward — see Finding #5); 5.4 standalone.

#### Cross-Epic Dependencies

Per epics §Sequencing & Dependencies: Epic 1 → 2 → {3, 4} → 5. Forward dependencies disallowed by best practices, but **outputs of earlier epics consumed by later epics is allowed**. The sequencing claims hold:
- Epic 2 consumes Epic 1's clean-plan baseline → ✅
- Epic 3 consumes Epic 2's local stack → ✅ (additive, non-breaking)
- Epic 4 can land in parallel with 3 → ✅
- Epic 5 synthesizes 1–4 → ✅

No epic claims a need for a future epic to function. ✅

### Findings

#### 🔴 Critical Violations

**None.** No epic with zero user value, no epic-on-future-epic forward dependency, no story that can't be completed within its epic.

#### 🟠 Major Issues

**Finding #1 — Story 1.1 (schema diff inventory) is a document-producing story, not a runnable capability**

- Story 1.1 produces an inventory document; subsequent stories consume it. The user gains no observable capability after 1.1 lands in isolation.
- **Mitigation context:** This is a defensible brownfield pre-flight investigation (PRD risk-mitigation explicitly identifies provider schema breakage as a top technical risk). The cost of skipping it would be blind migrations.
- **Recommendation:** Either (a) accept as an investigation story under brownfield conventions and document the rationale, or (b) merge with Story 1.2 so the bump and the schema diffs land together. **Preferred: keep as 1.1** for risk isolation, and add an explicit "investigation story" framing in the epic narrative.

**Finding #2 — Story 1.6 bundles end-to-end verification + MIGRATION.md authoring**

- Two distinct logical units: (a) clean-plan verification gate, (b) writing migration documentation.
- Could be split into 1.6a (verify clean plan) and 1.6b (author MIGRATION.md §2).
- **Recommendation:** Split is ideal but optional — current bundling is acceptable if the engineer treats them as sequential within one PR. Mark as "could-split" rather than "must-split."

**Finding #3 — Epic 2 has an in-epic forward dependency: Story 2.3 references Story 2.4's deliverable**

- Story 2.3 AC #4: "the existing `scripts/create-s3-bucket.sh` invocation is replaced with `scripts/create-state-bucket.sh` (delivered in Story 2.4)."
- 2.3 cannot complete without 2.4 already landed (or: 2.3 lands referencing a script that does not yet exist — broken intermediate state).
- **Recommendation:** **Reorder to land Story 2.4 (rename) before Story 2.3 (rewire).** Or merge 2.3 + 2.4 into a single story since they're tightly coupled. Document the corrected sequence in epics §Sequencing.

**Finding #4 — Gap #12 (from Step 3) re-classified as quality concern: NFR10 cannot be 100% met**

- The PRD's NFR10 requires *all five* listed platform workflows runnable via `act` on macOS. Stories cover 3 of 5 (`onboard-konnect-teams`, `deploy-dp`, `publish-api-configuration`). `developer-portal` and `test-sync-api-configuration` lack explicit `act` verification stories.
- **Recommendation:** Add to Epic 1 or Epic 2. Either:
  - Add an AC to Story 1.6 / 2.6 covering these workflows.
  - Add a new "Story 2.7 — Verify `developer-portal` and `test-sync-api-configuration` run via `act` against MinIO + Vault dev container."

**Finding #5 — Story 5.3 references Stories 5.2 and 5.4 as inputs**

- Story 5.3's "anchor-link into specific subsections" depends on 5.2's structure; "links to webapp/README.md" depends on 5.4 having landed.
- Within-epic dependencies are not forbidden, but should be made explicit.
- **Recommendation:** Document Epic 5's intra-epic order as 5.1 → 5.2 → 5.4 → 5.3 (or land 5.3 last). Currently the order is implicit.

#### 🟡 Minor Concerns

**Finding #6 — Epic title style inconsistency**

- Epic titles 1 and 5 lead with technical nouns ("Modernization", "Documentation Synthesis"). Epics 2, 3, 4 are user-or-capability-flavored.
- Cosmetic; does not affect implementation. Skipping.

**Finding #7 — Story 1.4 covers both Terraform trees in one story; siblings 1.2 / 1.3 split per tree**

- Asymmetry: 1.2 = bump tree A, 1.3 = bump tree B, 1.4 = state migrations in *both* trees. The migration scripts are very similar across trees — defensible as one story, but inconsistent with the 1.2/1.3 split.
- **Recommendation:** Acceptable; the engineer can split mid-implementation if PR size becomes unwieldy. No mandatory change.

**Finding #8 — `WHAT_TO_CHANGE.md` and `_bmad/` artifacts are present in working tree but not in scope**

- The repo currently has a `WHAT_TO_CHANGE.md` scratchpad (per epics doc note: "intentionally not tracked as a story-generating requirement") and `_bmad/`, `_bmad-output/`, `.agents/`, `.claude/` directories — none of which are story-generating.
- **Recommendation:** Confirm these are gitignored before merge to avoid landing planning artifacts in `main`. Cosmetic but worth catching.

**Finding #9 — No story exercises NFR8 pin verification for `decK v1.51.0` and Spectral ruleset**

- See Gap #10 from Step 3. Marginal coverage concern.

### Best Practices Compliance Checklist

For each epic:

| Check | E1 | E2 | E3 | E4 | E5 |
|-------|----|----|----|----|----|
| Delivers user value | ✅ | ✅ | ✅ | ✅ | ✅ |
| Functions independently (modulo prior-epic outputs) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Stories appropriately sized | ⚠️ (1.6 bundling) | ⚠️ (2.3↔2.4 coupling) | ✅ | ✅ | ✅ |
| No forward dependencies (within or cross-epic) | ✅ | ⚠️ (2.3→2.4 forward) | ✅ | ✅ | ⚠️ (5.3→5.2,5.4 implicit) |
| Brownfield migration patterns present | ✅ | ✅ | ✅ | ✅ | ✅ |
| Clear, testable acceptance criteria | ✅ | ✅ | ✅ | ✅ | ✅ |
| Traceability to FRs/NFRs maintained (FR Coverage Map) | ✅ | ✅ | ✅ | ✅ | ✅ |

### Quality Summary

**Overall:** Strong epic decomposition. Quality issues are real but localized and easily remediated:
- One tangible **major finding** (Finding #3, Story 2.3↔2.4 ordering) — fix before implementation.
- One tangible **major finding** (Finding #4, NFR10 coverage shortfall) — also a coverage gap from Step 3.
- Remaining findings (#1, #2, #5, #7, #8, #9) are minor or stylistic and do not block implementation.

No epic is a "technical milestone" in the negative sense; the brownfield refactor framing makes "modernization" and "documentation synthesis" valid epics with concrete user-value outcomes.

## Summary and Recommendations

### Overall Readiness Status

**🟡 NEEDS MINOR WORK** — Implementation can proceed after addressing 3 must-fix items. Planning artifacts (PRD, Architecture, Epics) are well-aligned, traceable, and rigorous. The PRD is mature, the Architecture introduces clear ADRs/patterns, and the epic decomposition reflects the PRD's risk-mitigation guidance. There are no critical structural defects, no missing FRs, and no zero-value technical-milestone epics. Remaining work is targeted clarification and minor reordering — not redesign.

### Critical Issues Requiring Immediate Action (Must-Fix Before Implementation)

**1. PRD ↔ Architecture ↔ Epics misalignment on FR30 (secrets backend)** *(Gap #6)*
- **The conflict:** PRD §Technical Success states "Konnect Vault replaces HashiCorp Vault as the secrets backend in the default path." Architecture ADR #001 (and Epics §Requirements Inventory) reverse this — HashiCorp Vault remains the sole backend; "selection" collapses to a `VAULT_ADDR` env-var swap. The ADR is consistent with the PRD's Risk Mitigation guidance, but the PRD's Technical Success bullet still claims the original direction.
- **Action:** Reconcile FR30 wording and the PRD's Technical Success bullet to match ADR #001. Update PRD or formally accept the ADR's reframing as a PRD amendment.
- **Owner:** Product (Jordi). Estimated effort: < 30 minutes.

**2. NFR10 coverage shortfall: `developer-portal` and `test-sync-api-configuration` not act-verified** *(Gap #12 / Finding #4)*
- **The conflict:** PRD NFR10 says "100% of platform workflows run end-to-end via `act`." Stories cover `onboard-konnect-teams` (2.6), `deploy-dp` (3.2), `publish-api-configuration` (4.5). Two of the five PRD-listed workflows are not covered by an explicit `act`-verification story.
- **Action:** Either (a) add a new "Story 2.7" or extend Story 2.6 with ACs running these two workflows via `act`, or (b) narrow NFR10's wording to the three covered workflows + a justification for excluding the other two.
- **Owner:** Engineering + Product. Estimated effort: 1–2 hours of epic editing; verification effort folds into the existing Epic 2 PR.

**3. FR4 — `scripts/check-deps.sh` referenced but not authored by any story** *(Gap #1)*
- **The conflict:** Story 2.6 references `scripts/check-deps.sh` as a precondition (in a Then clause), but no story explicitly creates it.
- **Action:** Add an AC to Story 2.6 (or split into a new Story 2.0 / 2.5b) to author `scripts/check-deps.sh` with the documented dependency list (Docker, `act`, `gh`, `terraform`, `helm`, `kubectl`) and actionable error messages on missing/incompatible tools.
- **Owner:** Engineering. Estimated effort: < 1 hour for story authoring; implementation effort is part of Epic 2.

### Should-Fix (Quality Improvements Worth Making Before Implementation)

**4. Story 2.3 ↔ Story 2.4 ordering** *(Finding #3)*
- Story 2.3 references Story 2.4's deliverable in an AC. Reorder to land 2.4 before 2.3, or merge them. Update epics §Sequencing.

**5. Capability-level parity verification for FR7–FR12, FR21, FR22** *(Gaps #3, #4)*
- Add discrete capability-verification ACs to Story 1.6 (or new sub-stories) covering: provision a fresh team (FR7), system-account token persisted (FR8), entitlement rejection (FR11), idempotent re-apply (FR12), `developer-portal` workflow apply (FR21), dashboards apply (FR22). Plan-zero-diff alone is insufficient for parity verification under the PRD's "functional parity" mandate.

**6. Document Epic 5 intra-epic ordering** *(Finding #5)*
- Make explicit: 5.1 → 5.2 → 5.4 → 5.3 (or land 5.3 last). Currently the order is implicit and Story 5.3 forward-references 5.2 and 5.4.

### Nice-to-Have (Defer or Accept)

**7. NFR8 pin verification for decK / Spectral** (Gap #10) — add an AC to Story 4.5 asserting the pinned versions remain unchanged.

**8. NFR6 `secrets: inherit` enforcement** (Gap #8) — optional lint rule; otherwise a code-review-enforced convention.

**9. NFR5 / NFR7 catch-all phrases** (Gaps #7, #9) — narrow the wording or accept as best-effort.

**10. NFR9 system-account token output guard** (Gap #11) — add a `terraform output -json | jq` AC to Story 1.2/1.3.

**11. NFR11 macOS support matrix** (Gap #13) — narrow to "single tested macOS version" or accept as best-effort.

**12. NFR13 / NFR17 broader error/drift verification** (Gaps #14, #15) — passive verification is acceptable.

**13. FR27 breaking-change docs policy** (Gap #5) — slot reserved; document in CONTRIBUTING.md.

**14. Story 1.1 / Story 1.6 framing** (Findings #1, #2) — accept as brownfield investigation + bundled verification-and-doc story.

**15. Story 1.4 / 1.2 / 1.3 sibling asymmetry** (Finding #7) — accept; engineer can split mid-implementation if PR size grows.

**16. Cosmetic** — Epic title style (Finding #6); confirm `_bmad/`, `WHAT_TO_CHANGE.md`, `_bmad-output/`, `.agents/`, `.claude/` are gitignored before merging the refactor (Finding #8).

### Recommended Next Steps

1. **Hold a 30-minute alignment session** to resolve must-fix #1 (FR30 secrets-backend reframing). The decision must be ratified at the PRD layer.
2. **Edit `_bmad-output/planning-artifacts/epics.md`** to add the must-fix story-level changes:
   - New AC or new Story 2.7 covering NFR10's two missing workflows.
   - New AC in Story 2.6 (or earlier) authoring `scripts/check-deps.sh`.
3. **Reorder Epic 2 stories** so 2.4 lands before 2.3 (or merge them).
4. **Add capability-verification ACs to Story 1.6** for FR7–FR12, FR21, FR22 (parity verification beyond plan-zero-diff).
5. **Document Epic 5 intra-epic order** in epics §Sequencing.
6. After the above edits, **re-run this readiness check** for the should-fix and minor items, OR proceed to implementation if you accept the residual minor risk on the should-fix items.
7. Once must-fix items #1–#3 are resolved, the project is **READY** for Phase 4 implementation. Sequencing recommended in PRD § Risk Mitigation: provider bump (Epic 1) → state backend + bootstrap (Epic 2) → k8s target (Epic 3) → contracts + lints (Epic 4) → docs synthesis + vendor strip (Epic 5).

### Final Note

This assessment identified:
- **0 critical structural defects.**
- **3 must-fix items** (FR30 alignment, NFR10 workflow coverage, FR4 missing script delivery).
- **3 should-fix items** for parity verification and sequencing hygiene.
- **10 nice-to-have items**, mostly NFR verification gaps that are defensible as passive coverage.

**Headline:** The PRD, Architecture, and Epics are tightly coupled, internally traceable, and ready for implementation modulo the three must-fix items. The PRD's brownfield framing and Architecture's pattern-driven decisions (P1–P6, ADR #001) flow cleanly through the epic decomposition. The single most consequential issue is the PRD↔ADR misalignment on the secrets backend (FR30) — that's a documentation/scoping fix, not a redesign.

These findings can be used to improve the artifacts before implementation, or you may choose to proceed as-is and address the must-fix items in flight (acceptable for #2 and #3; **not** for #1, which needs upstream resolution at the PRD layer).

---

**Date:** 2026-05-07
**Project:** kw-platform-ops
**Assessor:** Claude (bmad-check-implementation-readiness)
**Artifacts assessed:** `prd.md` (2026-05-06), `architecture.md` (2026-05-06), `epics.md` (2026-05-07)
