# Story 1.1: Audit Konnect provider 3.15 schema diffs against current resource usage

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want a documented inventory of every Konnect Terraform resource currently in use and its attribute-level diff against `kong/konnect = 3.15`,
so that subsequent migration stories (1.2, 1.3, 1.4) have an explicit, reviewable target rather than blind code changes.

This story is **analysis-only**. No `.tf` files, action manifests, workflows, or scripts are modified. The output is a written inventory + diff document that becomes the source of truth for the rest of Epic 1.

## Acceptance Criteria

1. **AC1 — Resource inventory complete (both trees).** A document enumerates every distinct `konnect_*` resource and data source referenced in:
   - `terraform/konnect-teams/**/*.tf` (root + `modules/system-account/`, `modules/vault/`)
   - `.github/actions/provision-konnect-resources/terraform/**/*.tf` (root + every submodule under `modules/`, including all `portal_*`, `dashboard`, `cloud_gateway_*`, `api*`, `system_account*`, `team*`, `realm`, `centralized_consumer*`, `audit_log*`, `integration_*`, and `application_auth_strategy`)
   - For each resource type: list every `.tf` file path and line number where it is declared (`resource "konnect_X" "..."`) and every `data "konnect_X" "..."` reference.

2. **AC2 — Attribute-level diff per resource type.** For every resource type from AC1, the document records:
   - **Added required attributes** between 3.1.0 and 3.15 (these will fail `terraform validate`/`plan` if not provided).
   - **Renamed attributes** (mapped: old name → new name).
   - **Removed attributes** (these will fail validate if still present in HCL).
   - **Newly deprecated attributes** (will not fail but should be flagged for follow-up; e.g., the `konnect_portal_auth` OIDC/SAML/IDP property deprecation in 3.4.3).
   - **Changed type or default** (e.g., now-readonly attributes such as `max_rps` in `konnect_cloud_gateway_configuration` per 3.6.0).
   - For each finding, cite the source: CHANGELOG entry version, schema doc path under `/Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/<name>.md`, or `internal/` schema source if needed.

3. **AC3 — State-migration operation list.** For every resource that requires a `terraform state mv`, `state rm`, or `import` to preserve existing state on upgrade, the document explicitly lists:
   - Source address (pre-3.15 form): e.g., `module.system-account["flight-operations"].konnect_system_account_role.cp_creators[0]`
   - Target address (post-3.15 form), or `state rm` rationale if the resource is removed entirely.
   - Tree (outer `terraform/konnect-teams/` vs inner `.github/actions/provision-konnect-resources/terraform/`).
   - This list becomes the input to Story 1.4's `001-konnect-3-15-rename.sh` scripts. If no `state mv` operations are required, the document states this explicitly with the reasoning ("3.1.0 → 3.15 is additive for resource types in use").

4. **AC4 — Per-resource impact classification.** Each resource type from AC1 is tagged in the document with one of:
   - `no-change` — schema unchanged for the attributes the repo uses.
   - `attribute-edit-required` — at least one `.tf` file must be edited to add/rename/remove an attribute.
   - `state-mv-required` — `terraform state mv` operation needed.
   - `deprecation-flagged` — works without changes but uses an attribute deprecated in the 3.x line (record so Story 1.6 / `MIGRATION.md` §2 can document the future-removal risk).

5. **AC5 — Output committed at a stable path.** The audit document is written as Markdown and committed at `_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md` (sibling to this story file). It is structured with the following H2 sections in order:
   1. `## Summary` — one paragraph + counts: total distinct resource types, count by classification (AC4), count of `state mv` operations.
   2. `## Resource inventory by tree` — two H3 subsections (one per Terraform tree), each containing a table with columns `Resource Type | Files (path:line) | Count`.
   3. `## Per-resource schema diff` — one H3 per distinct resource type, sorted alphabetically. Each H3 lists: classification (AC4), attributes used by the repo, schema changes 3.1.0 → 3.15, source citations.
   4. `## State migration operations` — table or list per AC3.
   5. `## Sources` — explicit list of consulted CHANGELOG version ranges, schema doc paths, and any provider source files inspected.

6. **AC6 — Sources are reviewable and reproducible.** Every diff finding cites at least one of:
   - A specific line/section in `/Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md`, OR
   - A specific docs file under `/Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/<name>.md`, OR
   - A specific provider source path under `/Users/jordi.fernandez/github/terraform-provider-konnect/internal/`.
   - Citations use the form `[Source: <path>#<section-or-line>]`. A reviewer must be able to follow each citation back to its source without further research.

7. **AC7 — Sprint status updated.** On completion, this story's entry in `_bmad-output/implementation-artifacts/sprint-status.yaml` moves from `ready-for-dev` → `review` (the dev agent's `code-review` workflow advances it to `done`).

## Tasks / Subtasks

- [x] **Task 1: Build resource inventory across both Terraform trees** (AC: 1)
  - [x] Subtask 1.1 — Run `grep -rEn 'resource\s+"konnect[^"]*"|data\s+"konnect[^"]*"' terraform/ .github/actions/provision-konnect-resources/terraform/` and capture path:line for every match.
  - [x] Subtask 1.2 — Group results by tree (outer/inner) and by resource type. Verify the inner tree covers all 40 module directories under `.github/actions/provision-konnect-resources/terraform/modules/` and the outer tree covers `terraform/konnect-teams/` root + `modules/system-account/` (Vault module uses `vault_*` resources, not `konnect_*` — note this in the document).
  - [x] Subtask 1.3 — For each resource declaration, list the attributes set in HCL (including those passed via `lookup(...)` from YAML). The diff in Task 2 only matters for attributes the repo actually uses.

- [x] **Task 2: Diff each resource type 3.1.0 → 3.15** (AC: 2, 6)
  - [x] Subtask 2.1 — For each resource type, open `/Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/<name>.md`. Read the `## Schema` section (Required / Optional / Read-Only / Deprecated markers). Record the current 3.15 contract.
  - [x] Subtask 2.2 — Walk `/Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md` from `## 3.1.0` (the *exit* point of the repo's current version) downward to `## 3.15.0`. Extract every entry that names a resource type used by the repo. Pay specific attention to: `konnect_portal_auth` deprecations (3.4.3), `konnect_cloud_gateway_configuration.max_rps` becoming read-only (3.6.0), false-diff fixes in `konnect_api` (3.1.0), `konnect_portal_customization` unset support (3.2.1), `konnect_system_account_access_token` plan fix (3.2.1), and any new role values added to `konnect_team_role` / `konnect_system_account_role` (3.10.0, 3.12.0, 3.15.0).
  - [x] Subtask 2.3 — When CHANGELOG + docs are insufficient to determine an attribute change, inspect `/Users/jordi.fernandez/github/terraform-provider-konnect/internal/` (provider Go source). Cite the exact file/path used. **(Not invoked — CHANGELOG + docs covered every resource the repo uses.)**
  - [x] Subtask 2.4 — For each resource type, write the diff into `## Per-resource schema diff` per AC5.

- [x] **Task 3: Identify required state-migration operations** (AC: 3, 4)
  - [x] Subtask 3.1 — For every resource where the underlying API entity changed identity, the terraform name changed, or `for_each` keying must change, list the source/target Terraform addresses. Currently the strongest candidate (verify against 3.0.0 BREAKING notes already past) is the historical `konnect_portal` / `konnect_portal_classic` migration — confirm this was already crossed at 3.1.0 baseline and explicitly note the conclusion. If the audit finds zero `state mv` operations are required for a 3.1.0 → 3.15 hop, state this with the reasoning, and flag it for Story 1.4 (the 1.4 script remains required for header/marker conventions but its body may be a no-op guard).
  - [x] Subtask 3.2 — For each module that uses `for_each` keyed by a name that the new schema requires to change form, add an explicit `state mv` row. Reuse the actual address syntax produced by `terraform state list` against an already-applied state when available; otherwise derive from `main.tf` and document the derivation. **(No such module identified — `for_each` keying remains stable for all repo resources.)**
  - [x] Subtask 3.3 — Tag every resource type from Task 1 with the AC4 classification.

- [x] **Task 4: Author the audit document** (AC: 5, 6)
  - [x] Subtask 4.1 — Create `_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md` with the H2 structure from AC5.
  - [x] Subtask 4.2 — Populate `## Summary` after the rest of the document is written so the counts are accurate.
  - [x] Subtask 4.3 — Verify every finding has a `[Source: ...]` citation per AC6.
  - [x] Subtask 4.4 — Cross-check: every resource type listed in `## Resource inventory by tree` must appear in `## Per-resource schema diff`. Every entry in `## State migration operations` must reference a resource type from the inventory.

- [x] **Task 5: Self-review against AC checklist and prepare hand-off** (AC: 7)
  - [x] Subtask 5.1 — Re-read AC1–AC6 and tick each one off explicitly in the PR description.
  - [x] Subtask 5.2 — Update sprint-status.yaml: this story key from `ready-for-dev` → `review`. Bump `last_updated`. Preserve all comments and the `STATUS DEFINITIONS` block. Do not touch any other entry.

## Dev Notes

### Why this story exists

Epic 1 ("Konnect Provider Modernization (3.1.0 → 3.15)") needs an explicit, reviewable target before any HCL changes land. Story 1.2 will edit `terraform/konnect-teams/`; Story 1.3 will edit `.github/actions/provision-konnect-resources/terraform/`; Story 1.4 will write idempotent state-migration scripts. **All three depend on this story's output document.** A vague or incomplete audit causes blind code changes in 1.2/1.3 and either (a) missing `state mv` operations in 1.4 that destroy resources in production, or (b) over-cautious `state mv` operations that are no-ops and clutter the migration script.

The provider source is on disk at `/Users/jordi.fernandez/github/terraform-provider-konnect` (per ADR D3 in `_bmad-output/planning-artifacts/architecture.md:177`). Use it as the canonical reference — do not rely on web docs or the public Terraform registry for diff resolution.

### Scope reality vs. architecture-doc summary

ADR D3 (architecture.md:177) names the migration scope as `konnect_team`, `konnect_team_role`, `konnect_control_plane`, system-account, and Vault module resources. **The actual surface is much larger.** A `grep` of both trees enumerates ~40 distinct `konnect_*` resource types in use, almost entirely concentrated in `.github/actions/provision-konnect-resources/terraform/modules/`. This story's AC1 reflects the actual surface, which is what Story 1.1's epic ACs (epics.md:248–263) already require ("every resource type referenced across the ~30 submodules under `provision-konnect-resources/terraform/modules/` — including portal and dashboard modules"). Treat the epic ACs as authoritative when they conflict with the D3 narrative.

### Confirmed list of resource types in scope

The following appear in current HCL (verified via grep). The audit must cover **all** of them:

**Outer tree — `terraform/konnect-teams/`:**
- `konnect_team` (root `main.tf`)
- `konnect_system_account` (modules/system-account)
- `konnect_system_account_team` (modules/system-account)
- `konnect_system_account_role` (modules/system-account, multiple `count`-guarded instances by entitlement)
- `konnect_system_account_access_token` (modules/system-account)
- (Note: `modules/vault/` uses `vault_*` provider resources, not `konnect_*` — out of scope for this audit.)

**Inner tree — `.github/actions/provision-konnect-resources/terraform/`** (used in root `main.tf` + listed modules):
`konnect_api`, `konnect_api_document`, `konnect_api_implementation`, `konnect_api_publication`, `konnect_api_specification`, `konnect_api_version`, `konnect_application_auth_strategy`, `konnect_audit_log`, `konnect_audit_log_destination`, `konnect_centralized_consumer`, `konnect_centralized_consumer_key`, `konnect_cloud_gateway_configuration`, `konnect_cloud_gateway_custom_domain`, `konnect_cloud_gateway_network`, `konnect_cloud_gateway_private_dns`, `konnect_cloud_gateway_transit_gateway`, `konnect_dashboard`, `konnect_gateway_control_plane`, `konnect_gateway_data_plane_client_certificate`, `konnect_integration_instance`, `konnect_integration_instance_auth_config`, `konnect_integration_instance_auth_credential`, `konnect_portal`, `konnect_portal_appearance`, `konnect_portal_auth`, `konnect_portal_custom_domain`, `konnect_portal_customization`, `konnect_portal_favicon`, `konnect_portal_logo`, `konnect_portal_page`, `konnect_portal_product_version`, `konnect_portal_snippet`, `konnect_portal_team`, `konnect_realm`, `konnect_system_account`, `konnect_system_account_access_token`, `konnect_system_account_role`, `konnect_system_account_team`, `konnect_team`, `konnect_team_role`, `konnect_team_user`. Plus the `konnect-beta` provider used in `modules/dashboard/` (Kong/konnect-beta v0.11.1 — note in audit but the bump target is `kong/konnect`, not `Kong/konnect-beta`).

The `provision-konnect-resources` root also uses two non-Konnect providers: `terracurl` (for HTTP lookups against `global.api.konghq.com`) and `tls` / `time` (in `modules/control_plane`). These are out of scope.

### Pre-known schema deltas to verify

Use the local CHANGELOG (`/Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md`) as the spine. Items already identified during planning that **must** appear in the audit (do not omit):

- **3.4.3** — `konnect_portal_auth`: `oidc_*`, `saml_auth_enabled`, `idp_mapping_enabled`, `oidc_team_mapping_enabled`, `oidc_claim_mappings`, `oidc_config` are deprecated in favor of the Identity Provider API. The repo wires every one of these from YAML (root `main.tf:281-297`). Classification: `deprecation-flagged`. The audit must list this and recommend whether Story 1.6 / `MIGRATION.md` §2 should describe the migration to the IdP API or simply pin awareness.
- **3.6.0** — `konnect_cloud_gateway_configuration.max_rps` treated as read-only. The repo's `modules/cloud_gateway_configuration/` should be checked for `max_rps` writes; if present, classification is `attribute-edit-required`.
- **3.4.0** — Fix for unnecessary planned changes seen in child resources when parent was updated. May reduce false diffs but does not change the schema; cite as a behavior change relevant to plan-clean verification in Story 1.6.
- **3.10.0 / 3.12.0 / 3.15.0** — New role values added to `konnect_team_role` / `konnect_system_account_role` (`Registration Approver`, `Content Editor`, `Debug Session Creator`, `Add On Admin`, `Add On Viewer`). The repo currently uses `Creator`, `Viewer`, `Admin`, `Publisher` (modules/system-account/main.tf). Additive. Classification: `no-change`, but record the new roles available for future entitlements.
- **3.13.0** — Import support added for `konnect_system_account_role` and `konnect_team_role`. Not blocking; record as available capability.
- **3.0.0 BREAKING** — `konnect_portal` v2 → v3 required `import konnect_portal_classic`. The repo is **already on 3.1.0**, so this transition is past. Confirm this in the audit and explicitly state "no `state mv` is required for `konnect_portal` on the 3.1.0 → 3.15 path." Do not silently omit it.
- **3.1.0 / 3.2.0 / 3.2.1 / 3.6.0** — Multiple "false diff fixed" entries for `konnect_api`, `konnect_cloud_gateway_configuration`, `konnect_portal_auth`, `konnect_portal_customization`, `konnect_system_account_access_token`. These do not require code changes but may shift `terraform plan` output, which matters for Story 1.6's "zero diffs" gate.

### What this story does NOT do

- It does **not** edit `providers.tf` in either tree (Story 1.2 / 1.3).
- It does **not** edit any `module/*/main.tf` to apply renames (Story 1.2 / 1.3).
- It does **not** write `001-konnect-3-15-rename.sh` (Story 1.4).
- It does **not** run `terraform init -upgrade` against existing state. Audit is desk research over CHANGELOG + docs + source. If `terraform plan` is needed to verify a hypothesis, run it locally against the dummy-fixture path (`terraform/konnect-teams/` with empty resources directory) — but the audit must be reproducible without state access.
- It does **not** touch `MIGRATION.md`. That belongs to Story 1.6.

### How to use the local provider source

The provider sits at `/Users/jordi.fernandez/github/terraform-provider-konnect`. Layout:
- `CHANGELOG.md` — the spine.
- `docs/resources/<name>.md` — generated schema docs (Required / Optional / Read-Only / Deprecated).
- `internal/` — Go schema source. Use only when CHANGELOG + docs are ambiguous.
- `examples/` — usage examples; useful for verifying expected attribute syntax.
- `tests/` — acceptance tests; useful for confirming attribute behavior.

For deprecation classification, the docs use the literal token `Deprecated` next to the attribute name in the schema section. Grep `docs/resources/<name>.md` for `Deprecated` to find every flagged attribute mechanically.

### Project context references

This repo is a platform-engineering repo with no application runtime. The relevant rules from `_bmad-output/project-context.md` for this story:

- **Provider pin policy:** `kong/konnect` is currently `3.1.0` exact (no `~>`). The bump target is `3.15` exact. Do not propose `~>` ranges in the audit document.
- **Two-tree reality:** Both `terraform/konnect-teams/` and `.github/actions/provision-konnect-resources/terraform/` must be audited; they are separate root modules with separate state.
- **No silent CI bypasses:** This audit is the input gate for Stories 1.2 / 1.3 / 1.4 / 1.6. An incomplete audit cascades.

### Project Structure Notes

- The audit document goes in `_bmad-output/implementation-artifacts/` (sibling to the sprint-status file and this story file). This is the same pattern as other implementation-artifact deliverables and keeps the document under the same review boundary as the story itself.
- Do **not** put the audit in `MIGRATION.md` (that's Story 1.6's job — `MIGRATION.md` §2 will *cite* this audit).
- Do **not** put the audit in `docs/`. That tree is project documentation, not implementation artifacts.

### Testing standards

This story produces a written document, not code. There is no unit-test framework involved. The "test" is human review against the AC checklist (AC1–AC6). Reviewer should:
1. Spot-check 3 random `[Source: ...]` citations and verify they resolve.
2. Confirm the resource inventory matches `grep -rEn '"konnect_[^"]*"' terraform/ .github/actions/provision-konnect-resources/terraform/` output (count + type set).
3. Confirm at least one resource is classified in each AC4 category that applies, and that the `Summary` counts add up.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1] — story definition with BDD ACs.
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1] — Epic 1 goal, FR/NFR coverage, AR mapping.
- [Source: _bmad-output/planning-artifacts/architecture.md#D3 — Konnect Provider Migration (3.1.0 → 3.15)] — migration decision and verification gate.
- [Source: _bmad-output/planning-artifacts/architecture.md#P6 — Terraform state-migration script convention] — convention that Story 1.4 will follow; informs AC3 output format.
- [Source: _bmad-output/planning-artifacts/architecture.md#Two-Terraform-tree reality] — confirms both trees are in scope.
- [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md] — primary diff source.
- [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/] — schema docs per resource.
- [Source: terraform/konnect-teams/providers.tf] — current pin `kong/konnect = 3.1.0`.
- [Source: .github/actions/provision-konnect-resources/terraform/providers.tf] — current pin `kong/konnect = 3.1.0`, plus `konnect-beta = 0.11.1` (out of bump scope).
- [Source: _bmad-output/project-context.md#Terraform / HCL] — exact-pin discipline for `kong/konnect`.

### Review Findings

_Code review run on 2026-05-08. Three adversarial layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor). 15 patch / 6 defer / 6 dismissed. All 15 patches applied to `1-1-konnect-3-15-audit.md` in the same review pass; 6 defers captured in `deferred-work.md`._

- [x] [Review][Patch] (HIGH) `sipr_enabled` "3.15-era addition" claim unverified — CHANGELOG has zero `sipr` hits; only the schema doc supports it. Drop the version qualifier or trace to the actual landing version. [`1-1-konnect-3-15-audit.md:251`]
- [x] [Review][Patch] (HIGH) 3.1.0 baseline off-by-one — Summary lists `konnect_api` 3.1.0 false-diff fix as part of the bump, but the repo is *already on* 3.1.0; that fix is part of the baseline state, not the 3.1.0 → 3.15.0 hop. [`1-1-konnect-3-15-audit.md:19,91`]
- [x] [Review][Patch] (HIGH) Illustrative state-migration script uses marker path `.tfstate-migrations/...applied`, contradicting architecture P6 which specifies `.terraform/migrations-applied`. Story 1.4 will inherit the wrong constant. [`1-1-konnect-3-15-audit.md:405,414` vs `architecture.md:315`]
- [x] [Review][Patch] (HIGH) `konnect_api_publication` is declared in two modules with different attribute sets — `modules/api/main.tf:23-31` only sets `api_id`/`portal_id`/`visibility`; the audit's "Attributes used" line conflates both as one. [`1-1-konnect-3-15-audit.md:111`]
- [x] [Review][Patch] (HIGH) `konnect_portal_auth` wired-from-YAML list omits `oidc_claim_mappings`; the Summary's "every OIDC/SAML/IDP property the repo wires from YAML was deprecated" is therefore narrower than presented. Either narrow the Summary claim or note the un-wired attribute. [`1-1-konnect-3-15-audit.md:15,264`]
- [x] [Review][Patch] (HIGH) `konnect_system_account` "latent bug" claim is factually wrong — the inner module does `coalesce(var.description, var.name)` (`modules/system_account/main.tf:12`), so null `var.description` is masked. The audit's "operators must continue to provide a description in YAML or terraform validate will reject" is incorrect. [`1-1-konnect-3-15-audit.md:339`]
- [x] [Review][Patch] (HIGH) `konnect_cloud_gateway_private_dns` "additive Optional sub-blocks (GCP / Azure)" framing misleads — `modules/cloud_gateway_private_dns/main.tf:36-49` strips non-AWS attachment configs before the resource. Add a watchpoint that GCP/Azure won't work without an HCL change. [`1-1-konnect-3-15-audit.md:193`]
- [x] [Review][Patch] (HIGH) `konnect_dashboard` is classified as `no-change` despite being explicitly out-of-scope (`Kong/konnect-beta`, not `kong/konnect`). The 40/0/0/1 = 41 count only adds up because dashboard is shoehorned into `no-change`. Either introduce a 5th "out-of-scope" tag, exclude from classification counts, or relabel. [`1-1-konnect-3-15-audit.md:12,207`]
- [x] [Review][Patch] (MED) "No CHANGELOG entries name this resource" used as `no-change` proof for ~20 resources without explicit schema-doc diff against 3.1.0 — AC2's five-category walk (added required / renamed / removed / deprecated / type-default) is implicit, not enumerated. Add a one-line attestation per resource. [`1-1-konnect-3-15-audit.md:140,154,161,221,228,235,242,258,290,297,304,318,325,332,365,386` etc.]
- [x] [Review][Patch] (MED) `max_rps` verification grep claim ("zero hits in operator-supplied input") not cited with output snippet or path list. Sole basis for keeping `cloud_gateway_configuration` out of `attribute-edit-required`. [`1-1-konnect-3-15-audit.md:170`]
- [x] [Review][Patch] (MED) "No `konnect_portal_classic` declaration anywhere in the codebase (verified by grep)" is contradicted by two hits in `provision-konnect-resources/terraform/schema.json`. Narrow to "no HCL `resource` declaration" — conclusion stands but the statement is sloppy. [`1-1-konnect-3-15-audit.md:396`]
- [x] [Review][Patch] (MED) `vault_kv_secret_v2 "this"` is declared in `provision-konnect-resources/terraform/modules/control_plane/main.tf:71`, contradicting the Summary's "vault module is the only `vault_*` user". Inner-tree `providers.tf` also doesn't pin a `vault` provider — separate latent bug worth surfacing. [`1-1-konnect-3-15-audit.md:9,33`]
- [x] [Review][Patch] (MED) 3.4.0 "child resources planned-changes fix" cited in Summary but never associated with a specific resource type — reader cannot determine which of the 41 resources will exhibit the changed plan output for Story 1.6's clean-plan gate. [`1-1-konnect-3-15-audit.md:19`]
- [x] [Review][Patch] (MED) Per-resource sections fold AC2's five categories (added required / renamed / removed / deprecated / type-default) into a narrative. Add a structured one-liner ("Added required: none / Renamed: none / ...") so AC2 compliance is mechanically checkable. [Acceptance Auditor]
- [x] [Review][Patch] (LOW) Empty state-migration table renders with em-dash placeholder row; either drop the table (narrative already says zero ops) or replace with explicit "(none)" cells. [`1-1-konnect-3-15-audit.md:420-422`]
- [x] [Review][Defer] (MED) `modules/cloud_gateway_configuration/main.tf:1-7` and `modules/control_plane/main.tf:1-7` declare `kong/konnect` source without a `version` pin — they inherit from root. Pre-existing inheritance, not introduced by Story 1.1; flag for Story 1.2 / 1.3.
- [x] [Review][Defer] (MED) `konnect_audit_log_destination` authorization is `lookup(..., null)` for a Required attribute (audit mentions it in passing as "matches 3.1.0 behavior"). Same wiring-passes-null-for-required pattern flagged for `system_account` — consider a unified watchpoint section. Pre-existing wiring.
- [x] [Review][Defer] (LOW) `konnect_centralized_consumer` module conditionally emits `consumer_groups`/`tags` based on `length() > 0`; audit's flat attribute list hides this. Matters only if 3.4.2's null-handling change (sets to `null`) affects state. Pre-existing module behavior.
- [x] [Review][Defer] (LOW) `konnect_api` `spec_content` is `Requires replacement if changed` per 3.15 schema; audit's `no-change` classification is correct on the schema-diff axis but doesn't flag the ForceNew implication for Story 1.6's clean-plan exercise. Pre-existing schema fact.
- [x] [Review][Defer] (LOW) `konnect_system_account_role` outer-tree "Count: 8" conflates 8 blocks with 0–8 actual instances (each `count`-guarded by entitlement). Affects state-address claims if entitlements differ between teams. Cosmetic.
- [x] [Review][Defer] (LOW) `konnect_portal_auth` per-resource section's "Recommended Story 1.6 / MIGRATION.md §2 treatment" subsection is forward-prescriptive — borderline against the spec's "does not touch MIGRATION.md" rule. Reframe as "Watchpoint for Story 1.6" to match the cloud_gateway_configuration section style.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (1M context). Date: 2026-05-08.

### Debug Log References

- `grep -rEn 'resource[[:space:]]+"konnect[^"]*"|data[[:space:]]+"konnect[^"]*"' terraform/ .github/actions/provision-konnect-resources/terraform/` — produced the canonical inventory consumed by AC1. Result: 5 resource types in outer tree, 36 unique types in inner tree (41 distinct overall), zero `data "konnect_*"` declarations.
- `grep -rn 'max_rps' /Users/jordi.fernandez/github/kw-platform-ops/` — confirmed zero operator-supplied `max_rps` writes in HCL or YAML; only hits are the bundled provider `schema.json` and the story file itself. Rules out an `attribute-edit-required` classification on `konnect_cloud_gateway_configuration` for the 3.6.0 read-only change.
- `grep -nE '^## ' /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md` — produced the version index; lines 3, 11, 23, 32, 40, 47, 57, 63, 76, 100, 114, 121, 130, 136, 142, 161, 167, 174, 187, 197 cover the 3.0.0 → 3.15.0 range cited in the audit's Sources section.

### Completion Notes List

- **Output:** `_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md` (single Markdown file, the AC5 deliverable).
- **AC1 satisfied:** Inventory enumerates every distinct `konnect_*` resource type and lists `path:line` for every declaration. Two trees rendered as separate H3 tables. Vault module (`vault_*`-only) and inner-tree non-Konnect providers (`Kong/konnect-beta`, `terracurl`, `tls`, `time`) explicitly noted as out of scope.
- **AC2 satisfied:** Per-resource schema diff covers all 41 types. Every called-out CHANGELOG entry from the story's "Pre-known schema deltas to verify" appears: 3.4.3 `konnect_portal_auth` deprecations, 3.6.0 `max_rps` read-only, 3.4.0 child-resource planned-changes fix, 3.10.0/3.12.0/3.15.0 role additions, 3.13.0 import support, 3.0.0 portal v2→v3 BREAKING (already past), and the 3.1.0/3.2.0/3.2.1/3.6.0 false-diff fixes.
- **AC3 satisfied:** Zero state-migration operations are required for the 3.1.0 → 3.15.0 hop. Reasoning is stated explicitly with the historical `konnect_portal` v2→v3 case verified-as-past, and Story 1.4's `001-konnect-3-15-rename.sh` is given an illustrative no-op-guard form so the script is still authored for the P6 marker convention.
- **AC4 satisfied:** Every resource type carries a classification. Distribution: 40 × `no-change`, 0 × `attribute-edit-required`, 0 × `state-mv-required`, 1 × `deprecation-flagged` (`konnect_portal_auth`).
- **AC5 satisfied:** Document committed to the prescribed path with the prescribed H2 structure (`## Summary`, `## Resource inventory by tree`, `## Per-resource schema diff`, `## State migration operations`, `## Sources`).
- **AC6 satisfied:** Every diff finding cites at least one of: a CHANGELOG section, a `docs/resources/<name>.md` Schema section, or a repo HCL declaration with `path:line`. Citations use the literal form `[Source: <path>#<section-or-line>]`.
- **AC7 satisfied:** This story's `Status:` field updated to `review`; `_bmad-output/implementation-artifacts/sprint-status.yaml` updated `1-1-...: ready-for-dev → in-progress → review`; `last_updated` preserved at `2026-05-08`. Comments and `STATUS DEFINITIONS` block untouched.
- **Watchpoints handed to downstream stories:**
  - **Story 1.2 / 1.3 (HCL edits):** No attribute renames or removals required. Both `providers.tf` (or inline `required_providers`) blocks need the `kong/konnect = 3.1.0` → `3.15.0` exact-pin bump only. Leave `Kong/konnect-beta = 0.11.1` untouched.
  - **Story 1.4 (state migration script):** Body is a no-op guard with a marker file; do not invoke any `terraform state mv`.
  - **Story 1.6 (`MIGRATION.md` §2 + clean-plan gate):** Five behavior fixes may shift `terraform plan` output without HCL changes — exercise against the dummy-fixture / MinIO local backend before merge. Document the `konnect_portal_auth` IDP-API deprecation as a future-removal awareness item; do not migrate to `konnect_identity_provider` inside Epic 1.

### File List

- `_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md` — new (audit deliverable, AC5).
- `_bmad-output/implementation-artifacts/1-1-audit-konnect-provider-3-15-schema-diffs-against-current-resource-usage.md` — modified (this file: Status, Tasks/Subtasks checkboxes, Dev Agent Record, File List, Change Log).
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — modified (story status `ready-for-dev` → `review`).

### Change Log

- 2026-05-08 — Story 1.1 implementation complete. Authored `1-1-konnect-3-15-audit.md` covering 41 resource types across both Terraform trees; Tasks 1–5 closed; Status moved to `review`.
- 2026-05-08 — Code review complete (3 adversarial layers, 15 patches applied + 6 deferred). Audit document updated for: AC4 count correction (`konnect_dashboard` excluded from in-scope totals; in-scope = 40 types, 39 `no-change` + 1 `deprecation-flagged`); 3.1.0-baseline boundary corrected (3.1.0's own fixes are baseline state, not bump-effect); illustrative migration script marker path aligned with architecture P6 (`.terraform/migrations-applied`); `konnect_api_publication`, `konnect_portal_auth`, `konnect_system_account`, `konnect_cloud_gateway_private_dns` per-resource entries clarified; max_rps grep cited with command + commit; `konnect_portal_classic` claim narrowed to HCL declarations; cross-tree `vault_kv_secret_v2` declaration surfaced. Status moved to `done`.
