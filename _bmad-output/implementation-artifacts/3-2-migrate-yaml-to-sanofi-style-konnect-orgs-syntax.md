# Story 3.2: Migrate YAML to Sanofi-style `konnect/orgs/<org>/` syntax

Status: done

## Story

As a platform engineer,
I want all Konnect resource data declared under `konnect/orgs/<org>/` using the Sanofi reference syntax,
so that this repository has one declarative source of truth for every supported Konnect entity.

## Acceptance Criteria

1. **Given** the Sanofi reference pattern and the `konnect/orgs/konnect/` directory
   **When** this repository's YAML is migrated
   **Then** the target structure has one org directory, one or more YAML files grouped by resource type, and top-level keys consumed by `fileset()` + `yamldecode()` + `merge()` in `terraform/konnect/main.tf`

2. **Given** existing type-tagged resource files under `konnect/auth-identity/` and `konnect/teams/*/`
   **When** their data is migrated
   **Then** equivalent declarations exist under `konnect/orgs/konnect/`
   **And** the old `resources: [{ type: ... }]` schema is no longer the primary provisioning syntax

3. **Given** existing team YAML under `teams/*.yaml` and `konnect/orgs/konnect/teams.yaml`
   **When** teams are migrated
   **Then** team roles use the Sanofi/provider-3.15 `roles` shape with `name`, `entity_type_name`, optional `entity_region`, and optional `entity_names`
   **And** legacy `control_plane_roles`, `api_roles`, and `entitlements` are replaced or translated in `konnect/orgs/konnect/teams.yaml`

4. **Given** system accounts are generated per team automatically by the `team_system_accounts` module
   **When** the YAML migration is complete
   **Then** each team declared in `konnect/orgs/konnect/teams.yaml` automatically yields a HashiCorp Vault entry at `system-accounts/sa-<team-name>` (via the existing `team_vault` module wiring in `terraform/konnect/main.tf`)
   **And** system account tokens are never stored in YAML, Terraform outputs, or workflow logs

5. **Given** identity-provider and portal auth configurations require OIDC client secrets
   **When** those resources are declared in `konnect/orgs/konnect/`
   **Then** committed YAML contains only `oidc_client_secret_ref: <key>` (a reference into `var.sensitive_vars`) — no literal `oidc_client_secret` values

6. **Given** the YAML migration is complete
   **When** `terraform init -backend=false && terraform validate` runs in `terraform/konnect/`
   **Then** both pass with no errors — confirming the migrated YAML is structurally valid against the unified module

## Tasks / Subtasks

- [x] Migrate team roles in `konnect/orgs/konnect/teams.yaml` to Sanofi `roles` format. (AC: 2, 3)
  - [x] Replace `control_plane_roles` entries with `roles` entries using `entity_type_name: "Control Planes"`.
  - [x] Replace `api_roles` entries with `roles` entries using `entity_type_name: "APIs"`.
  - [x] Preserve `labels` and `description` on each team — do not drop them.
  - [x] Do NOT add `entitlements` — that field was legacy validation-only and is not used by the unified module.
  - [x] Apply the transformation to both `flight-operations` and `ground-operations` teams.
- [x] Complete `konnect/orgs/konnect/portals.yaml` with data present in `konnect/developer-portal/config.yaml` but missing from the orgs file. (AC: 1, 2)
  - [x] Add `robots:` field to the `portal_customizations:` entry (multi-line string from `developer-portal/config.yaml`).
  - [x] Add `spec_renderer:` field to the `portal_customizations:` entry.
  - [x] Do NOT add `js:` — it is not in `portal_customization_allowed_keys` in `terraform/konnect/main.tf` and will fail Terraform validation.
  - [x] Verify `portal_customization_allowed_keys` check passes: allowed keys are `portal_name`, `css`, `layout`, `robots`, `menu`, `spec_renderer`, `theme`.
- [x] Verify committed YAML in `konnect/orgs/konnect/identity-provider.yaml` uses `oidc_client_secret_ref` — NOT `oidc_client_secret`. (AC: 5)
  - [x] Confirm the file has `oidc_client_secret_ref: idp_client_secret` (already done in Story 3.1; verify it is still correct).
  - [x] Ensure `konnect/auth-identity/resources.yaml` is NOT referenced by the unified Terraform module (it only reads `konnect/orgs/konnect/*.yaml`).
- [x] Run validation checks in `terraform/konnect/`. (AC: 6)
  - [x] Run `terraform fmt -check -recursive` — fix any formatting drift.
  - [x] Run `terraform init -backend=false` — provider plugins must download successfully.
  - [x] Run `terraform validate` — must pass with zero errors.
  - [x] If `terraform validate` fails due to YAML issues, fix the YAML and re-run until clean.

## Dev Notes

### Core Migration: Teams Role Format

`konnect/orgs/konnect/teams.yaml` currently uses the **legacy role format**:

```yaml
teams:
  - name: flight-operations
    description: Flight ops teams
    control_plane_roles:
      - entity_id: "*"
        region: eu
        role: Creator
    api_roles:
      - entity_id: "*"
        region: eu
        role: Creator
      - entity_id: "*"
        region: eu
        role: Viewer
      - entity_id: "*"
        region: eu
        role: Publisher
    labels:
      TID: KTEAM_00001
```

The **target Sanofi `roles` format** is:

```yaml
teams:
  - name: flight-operations
    description: Flight ops teams
    roles:
      - name: Creator
        entity_type_name: Control Planes
        entity_region: eu
        entity_names: ["*"]
      - name: Creator
        entity_type_name: APIs
        entity_region: eu
        entity_names: ["*"]
      - name: Viewer
        entity_type_name: APIs
        entity_region: eu
        entity_names: ["*"]
      - name: Publisher
        entity_type_name: APIs
        entity_region: eu
        entity_names: ["*"]
    labels:
      TID: KTEAM_00001
```

**Field mapping rules** (from `terraform/konnect/main.tf` local `sanofi_team_role_bindings`):

| Legacy field     | Sanofi field          | Notes                                                   |
| ---------------- | --------------------- | ------------------------------------------------------- |
| `role: Creator`  | `name: Creator`       | Role name identical                                     |
| (from block key) | `entity_type_name`    | `"Control Planes"` for CP roles, `"APIs"` for API roles |
| `region: eu`     | `entity_region: eu`   | Optional; defaults to `var.konnect_region`              |
| `entity_id: "*"` | `entity_names: ["*"]` | List of entity names/IDs or `["*"]` for all             |

**Ground-operations** has an additional `Viewer` for control planes — translate that too.

> **Important:** The `terraform/konnect/main.tf` module already handles BOTH formats via separate local blocks (`sanofi_team_role_bindings`, `legacy_team_control_plane_role_bindings`, `legacy_team_api_role_bindings`). The legacy locals will simply produce empty lists after this migration, which is correct. Do NOT remove those local blocks from `main.tf` in this story — that is clean-up for Story 3.4.

### Portal YAML Completion

`konnect/orgs/konnect/portals.yaml` currently has `portal_customizations:` but is **missing** two fields that exist in `konnect/developer-portal/config.yaml`:

- `robots:` — robots.txt content string (multi-line)
- `spec_renderer:` — object `{ infinite_scroll: true, show_schemas: true, try_it_insomnia: true, try_it_ui: true }`

Both are in `portal_customization_allowed_keys` in `main.tf:218` and will be passed through. Add them to the `portal_customizations:` entry in `portals.yaml`.

**Do NOT add** `js:` — it is explicitly NOT in the allowed-keys set and would cause `terraform validate` to fail with the `portal_customization_unsupported_keys` precondition.

### Identity Provider Secret Pattern

`konnect/orgs/konnect/identity-provider.yaml` already uses the correct pattern (updated in Story 3.1):

```yaml
oidc_client_secret_ref: idp_client_secret
```

`idp_client_secret` is a key name looked up from `var.sensitive_vars` at plan/apply time. It is never committed to YAML. The `konnect/auth-identity/resources.yaml` legacy file contains a hardcoded placeholder `oidc_client_secret: my-client-secret` — this file is NOT read by the unified Terraform module (`terraform/konnect/` only reads `konnect/orgs/konnect/*.yaml`), so it poses no runtime risk. Do NOT delete it in this story; retirement is Story 3.4.

### System Accounts: Auto-Created Per Team

The `terraform/konnect/main.tf` has two separate system account mechanisms:

**STEP 2 — Per-team system accounts (automatic):**
```hcl
module "team_system_accounts" {
  source   = "./modules/team_system_account"
  for_each = module.teams
  ...
}
module "team_vault" {
  source   = "./modules/team_vault"
  for_each = var.create_team_vault_secrets ? module.teams : {}
  system_account_secret_path = "system-accounts/sa-${local.sanitized_team_names[each.key]}"
  ...
}
```

This automatically creates one system account and Vault secret per declared team. No explicit `system_accounts:` YAML key is needed to satisfy AC 4. Both `flight-operations` and `ground-operations` will receive their Vault entries automatically at `system-accounts/sa-flight-operations` and `system-accounts/sa-ground-operations` once Story 3.3 runs the workflow.

**STEP 3 — Explicit system accounts (optional, from `system_accounts:` YAML key):**
This mechanism exists for additional, non-team-scoped automation accounts. Story 3.2 does not require any such accounts. Do not add a `system_accounts.yaml` unless a specific non-team automation account is needed.

### Current State of `konnect/orgs/konnect/`

| File                           | Status                                                            | Action in this story          |
| ------------------------------ | ----------------------------------------------------------------- | ----------------------------- |
| `authentication-settings.yaml` | ✅ Already Sanofi-style                                            | No change                     |
| `control-planes.yaml`          | ✅ Already Sanofi-style                                            | No change                     |
| `dashboards.yaml`              | ✅ Already Sanofi-style                                            | No change                     |
| `identity-provider.yaml`       | ✅ Fixed in Story 3.1 (uses `oidc_client_secret_ref`)              | Verify only                   |
| `portals.yaml`                 | ⚠️ Missing `robots` and `spec_renderer` in `portal_customizations` | Add missing fields            |
| `teams.yaml`                   | ❌ Legacy `control_plane_roles`/`api_roles` format                 | **Migrate to `roles` format** |

### Legacy Files NOT to Touch

The following files remain unchanged until Story 3.4 retires them:
- `teams/flight-operations.yaml` — legacy per-team declaration (triggers `onboard-konnect-teams` workflow)
- `teams/ground-operations.yaml` — same
- `konnect/auth-identity/resources.yaml` — legacy type-tagged auth/identity resources
- `konnect/teams/flight-operations/resources.yaml` — legacy type-tagged per-team resources
- `konnect/teams/ground-operations/resources.yaml` — same
- `konnect/developer-portal/config.yaml` — legacy developer portal config
- `konnect/dashboards/dashboard-config.yaml` — legacy dashboard config

Do NOT modify or delete any of these in this story. The legacy workflows still reference them, and Story 3.4 (end-to-end verification) gates their removal.

### Terraform Module YAML Merge Semantics

The `main.tf` config loading uses a robust merge strategy (fixed in Story 3.1 review):

```hcl
config_values_by_key = {
  for key in local.config_keys : key =>
    [for document in local.config_documents : document[key]
     if contains(keys(document), key)]
}
org_config = {
  for key, values in local.config_values_by_key : key => (
    alltrue([for value in values : can(tolist(value))]) ?
      flatten([for value in values : tolist(value)]) :          # lists → flatten
    alltrue([for value in values : can(tomap(value))]) ?
      merge([for value in values : tomap(value)]...) :          # objects → deep merge
    values[length(values) - 1]                                   # scalar → last wins
  )
}
```

Multiple `*.yaml` files under `konnect/orgs/konnect/` that share the same top-level key will have their lists **flattened together**. This means:
- If both `teams.yaml` and a hypothetical second file declare a `teams:` list, both lists are merged. Safe for this story since `teams:` only appears in `teams.yaml`.
- File order is stable (`sort(fileset(...))` = alphabetical). Do NOT rely on order within a single file for correctness.

### Validation Gate

Minimum required checks for this story:

```bash
cd terraform/konnect
terraform fmt -check -recursive      # no formatting drift
terraform init -backend=false        # provider download
terraform validate                   # structural + YAML validation via preconditions
```

`terraform validate` triggers the `terraform_data.validate_org_config` preconditions:
- `identity_provider_secret_violations == 0` — no hardcoded `oidc_client_secret`
- `portal_auth_secret_violations == 0` — no hardcoded portal OIDC secrets
- `portal_customization_unsupported_keys == 0` — no unsupported portal customization keys
- `sanitized_team_names` are unique and non-empty

Do **NOT** add `continue-on-error: true`, `|| true`, or any bypass to these checks.

### Architecture Compliance

- Follow project Terraform conventions: no HCL changes in this story — only YAML changes in `konnect/orgs/konnect/`. [Source: `_bmad-output/project-context.md#Terraform / HCL`]
- Keep `oidc_client_secret_ref` pattern (not `oidc_client_secret`) for identity provider and portal auth secrets. [Source: `_bmad-output/project-context.md#YAML (source-of-truth files)` + `terraform/konnect/main.tf:260–275`]
- Story does NOT create or modify any workflows, Terraform modules, or shell scripts. Scope is `konnect/orgs/konnect/` YAML only. [Source: `_bmad-output/planning-artifacts/epics.md#Story 3.2`]
- ADR #002 designates `konnect/orgs/<org>/*.yaml` as the unified YAML source of truth. The Sanofi `roles` format is the accepted pattern. [Source: `_bmad-output/planning-artifacts/architecture.md#ADR #002`]

### Previous Story Intelligence (3.1)

- Story 3.1 already fixed `identity-provider.yaml` to use `oidc_client_secret_ref`. Verify this is still in place before submitting.
- Story 3.1 removed `js:` from `portals.yaml` during the review cycle because it was in `portal_customization_unsupported_keys`. Do NOT re-add `js:`.
- `portals.yaml` was modified in the Story 3.1 commit (`531510b`) — check its current content carefully before assuming the pre-story state.
- `terraform/konnect/.terraform.lock.hcl` is already committed. Running `terraform init -backend=false` should be fast (uses cached providers). If provider download fails for network reasons, document the exact command and re-run when network is available — same pattern as in Story 3.1 debug log.
- Story 3.1 review surfaced a `portal customization and auth inputs are accepted but ignored` finding — this was patched. Do NOT re-introduce unconnected portal customization inputs.

### Git Intelligence

- **Commit `531510b`** (`Story 3.1`): Created the unified `terraform/konnect/` root. Changed `konnect/orgs/konnect/identity-provider.yaml` (removed hardcoded secret) and `konnect/orgs/konnect/portals.yaml` (removed unsupported `js:` key). These are the direct predecessors to the files modified in this story.
- **Commit `e965e9e`** (`Correct course`): Sprint change proposal that introduced the current `konnect/orgs/konnect/*.yaml` files as a partial migration. This is where `control-planes.yaml`, `authentication-settings.yaml`, and the partial `teams.yaml` were introduced.
- **Commit `774e502`**: Added structured API/control-plane roles to `teams/` (legacy files) and implemented `for_each` keying in `konnect-teams/`. The legacy `control_plane_roles`/`api_roles` format in `konnect/orgs/konnect/teams.yaml` mirrors this commit's role shape — safe to migrate.

### Anti-Patterns To Avoid

- Do NOT add `oidc_client_secret` (literal value) to any YAML file in `konnect/orgs/konnect/`. Use `oidc_client_secret_ref` only.
- Do NOT add `js:` to `portal_customizations:` in `portals.yaml` — it will fail Terraform validation.
- Do NOT modify `terraform/konnect/main.tf` or any Terraform module in this story. HCL is not in scope.
- Do NOT delete or retire legacy files (`teams/`, `konnect/auth-identity/`, `konnect/teams/`, `konnect/developer-portal/`) — retirement is Story 3.4.
- Do NOT add per-team entries to a `system_accounts:` key (that would duplicate the auto-created accounts from `team_system_accounts` module). The per-team system accounts are auto-created from the `teams:` list.
- Do NOT remove `control_plane_roles` / `api_roles` legacy handling locals from `main.tf` — they are still harmless and removal is Story 3.4 clean-up.

### Project Context Reference

- Core agent rules and project conventions are in `_bmad-output/project-context.md`. Key relevant section: `YAML (source-of-truth files)` — every resource YAML must have a top-level `name`; entitlements/new fields must be validated before reaching Terraform.
- No UX artifact exists for this project. This story has no frontend or operator-UI work.
- Validation gates must not be bypassed. [Source: `_bmad-output/project-context.md#Testing & Validation Rules`]

### Story Completion Status

Ultimate context engine analysis completed — comprehensive developer guide created.

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4.6 (GitHub Copilot)

### Debug Log References

- `terraform fmt -check -recursive` → exit 0, no drift
- `terraform init -backend=false` → exit 0, providers reused from lock file
- `terraform validate` → exit 0, `Success! The configuration is valid.`

### Completion Notes List

- Migrated `konnect/orgs/konnect/teams.yaml`: replaced `control_plane_roles` + `api_roles` legacy blocks on both teams with flat `roles` list using `entity_type_name`, `entity_region`, and `entity_names`. `flight-operations` gets 4 role entries (1 CP + 3 API); `ground-operations` gets 5 (2 CP + 3 API). `labels` and `description` preserved on both teams. No `entitlements` added.
- Completed `konnect/orgs/konnect/portals.yaml`: added `robots:` (folded `>-` scalar, copied verbatim from `konnect/developer-portal/config.yaml`) and `spec_renderer:` (`infinite_scroll`, `show_schemas`, `try_it_insomnia`, `try_it_ui`) to the `portal_customizations:` entry. `js:` was intentionally NOT added.
- Verified `konnect/orgs/konnect/identity-provider.yaml` retains `oidc_client_secret_ref: idp_client_secret` from Story 3.1. No literal secret committed.
- All three Terraform validation commands passed with zero errors.

### File List

- `konnect/orgs/konnect/teams.yaml`
- `konnect/orgs/konnect/portals.yaml`

### Change Log

- 2026-05-21: Migrated both teams in `teams.yaml` from legacy `control_plane_roles`/`api_roles` format to Sanofi `roles` format (AC 2, 3)
- 2026-05-21: Added `robots:` and `spec_renderer:` to `portal_customizations:` in `portals.yaml` (AC 1, 2)

### Review Findings

- [ ] [Review][Decision] AC6 verification gap — `terraform validate` is claimed to pass (Debug Log) but no CI artifact or execution trace is in the diff; should validation be run now to confirm AC6?
- [x] [Review][Patch] `robots:` uses `>-` (folded scalar) — all directives collapse to one line; `Sitemap:` key and URL must also be on the same line [`konnect/orgs/konnect/portals.yaml:77-84`]
- [x] [Review][Defer] Placeholder domain `some-random-domain-347t783t5q53.com` in robots Sitemap URL [`konnect/orgs/konnect/portals.yaml:83`] — deferred, pre-existing (faithfully migrated from `developer-portal/config.yaml`)
- [x] [Review][Defer] `Allow: /apis/` and `Allow: /docs/` are robots.txt no-ops (everything not Disallowed is allowed by default) [`konnect/orgs/konnect/portals.yaml:79-80`] — deferred, pre-existing
- [x] [Review][Defer] `spec_renderer` enables `try_it_insomnia` and `try_it_ui` simultaneously — dual try-it clients, security exposure of auth flows [`konnect/orgs/konnect/portals.yaml:86-89`] — deferred, faithfully migrated from source
- [x] [Review][Defer] All role entries use `entity_names: ["*"]` wildcard and hardcoded `entity_region: eu` — no least-privilege scoping, no multi-region support [`konnect/orgs/konnect/teams.yaml`] — deferred, equivalent to legacy design
- [x] [Review][Defer] `entity_type_name` string values have no YAML-layer schema enforcement — capitalisation typo silently passes and produces null bindings at runtime [`konnect/orgs/konnect/teams.yaml`] — deferred, infrastructure validation gap
- [x] [Review][Defer] Role entries missing `name` or `entity_type_name` produce null bindings silently — no yq pre-flight guard for required role fields [`konnect/orgs/konnect/teams.yaml`] — deferred, infrastructure gap
- [x] [Review][Defer] `entity_names: []` empty list produces zero Terraform role bindings with no error [`konnect/orgs/konnect/teams.yaml`] — deferred, infrastructure gap
- [x] [Review][Defer] `konnect/auth-identity/resources.yaml` retains `oidc_client_secret: my-client-secret` placeholder — outside Story 3.2 scope [`konnect/auth-identity/resources.yaml`] — deferred, explicitly scoped to Story 3.4
- [x] [Review][Defer] `theme.colors` extra fields (`secondary`, `accent`, `background`, `text`) are silently dropped by Terraform type coercion [`konnect/orgs/konnect/portals.yaml`] — deferred, pre-existing
- 2026-05-21: Verified `identity-provider.yaml` uses `oidc_client_secret_ref` (AC 5)
- 2026-05-21: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate` all pass (AC 6)