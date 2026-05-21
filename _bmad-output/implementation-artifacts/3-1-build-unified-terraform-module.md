# Story 3.1: Build unified Terraform module `terraform/konnect/`

Status: done

## Story

As a platform engineer,
I want a single Terraform module that reads all Konnect resource declarations from `konnect/orgs/<org>/*.yaml`,
so that teams, system accounts, control planes, control-plane children, portals, APIs, auth/identity, dashboards, and other supported Konnect entities are managed in one plan/apply cycle.

## Acceptance Criteria

1. Given `konnect/orgs/<org>/` contains multiple YAML files, when the module runs `fileset()` + `yamldecode()` + `merge()` over all `*.yaml` files, then it resolves Sanofi-style top-level keys such as `labels`, `control_plane_groups`, `control_planes`, `teams`, `system_accounts`, `application_auth_strategies`, `portals`, `authentication_settings`, `identity_provider`, and `dashboards`, and the module can be extended with additional top-level keys without changing the workflow contract or state layout.
2. Given control planes include nested Konnect gateway entities, when the module plans those control planes, then nested declarations for services, routes, upstreams, vaults, partials, custom plugins, global plugins, service plugins, and route plugins are handled by reusable submodules adapted from the Sanofi reference and the existing `provision-konnect-resources` Terraform modules.
3. Given API and portal resource modules already exist under `.github/actions/provision-konnect-resources/terraform/modules/`, when the unified module is built, then supported modules are moved, reused, or wrapped from `terraform/konnect/` so there is one Terraform implementation behind Konnect provisioning, not a second type-tagged implementation.
4. Given `var.org = "konnect"`, when Terraform initializes, then the backend key is `konnect/orgs/konnect/terraform.tfstate` and the backend bucket is a single shared S3/MinIO bucket, not `kw.konnect.team.resources.<team>`.
5. Given the module is complete, when `terraform fmt -check -recursive` and `terraform validate` run in `terraform/konnect/`, then both pass with no errors.

## Tasks / Subtasks

- [x] Create the new Terraform root additively under `terraform/konnect/`. (AC: 1, 4, 5)
  - [x] Add `backend.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, `main.tf`, `config.minio.tfbackend`, and `config.s3.tfbackend`.
  - [x] Use the existing P1 backend pattern from Epic 2, but set the root backend key to `konnect/orgs/konnect/terraform.tfstate` for the default org.
  - [x] Do not modify, retire, or repoint `terraform/konnect-teams/` or `.github/actions/provision-konnect-resources/terraform/` in this story.
- [x] Implement org-config loading from Sanofi-style YAML. (AC: 1)
  - [x] Add variables for `org`, `config_file_path` or `config_dir`, `konnect_server_url`, `konnect_access_token` or `konnect_token`, `konnect_region`, `vault_address`, and `vault_token`.
  - [x] Load `*.yaml` from `konnect/orgs/<org>/` with `fileset()` + `yamldecode()` + `merge([... ]...)`.
  - [x] Default absent top-level keys to empty collections or null singleton objects so partial org configs validate.
- [x] Reuse/adapt existing modules instead of reimplementing provider resources. (AC: 2, 3)
  - [x] Copy or wrap relevant modules from `.github/actions/provision-konnect-resources/terraform/modules/` into `terraform/konnect/modules/` for API, portal, dashboard, auth/identity, system-account, team, and control-plane support.
  - [x] Adapt Sanofi reference modules only where they add missing nested gateway coverage: `control-plane` services, routes, upstreams, vaults, partials, custom plugins, global plugins, service plugins, and route plugins.
  - [x] Preserve provider alias requirements for modules that need `konnect-beta` today, especially dashboard provisioning.
- [x] Preserve HashiCorp Vault token storage. (AC: 3)
  - [x] Reuse/adapt `terraform/konnect-teams/modules/system-account` and `terraform/konnect-teams/modules/vault` behavior for per-team system-account tokens.
  - [x] Store tokens at `system-accounts/sa-<team-name>` or an explicitly compatible path; never expose tokens through non-sensitive outputs, YAML, or logs.
  - [x] Do not copy Sanofi reference AWS Secrets Manager behavior for system-account tokens into this repo.
- [x] Normalize Sanofi-style team and system-account roles without breaking current examples. (AC: 1, 3)
  - [x] Support `roles` entries with `name`, `entity_type_name`, optional `entity_region`, and optional `entity_names`.
  - [x] Convert `entity_names` to concrete IDs after dependent resources are created where possible; preserve wildcard `*` semantics.
  - [x] Do not keep the old type-tagged `resources: [{ type: ... }]` parser as the primary model for this root.
- [x] Validate the new root locally. (AC: 5)
  - [x] Run `terraform fmt -check -recursive` in `terraform/konnect/`.
  - [x] Run `terraform init -backend=false` and `terraform validate` in `terraform/konnect/` so validation does not need live MinIO/AWS state.
  - [x] If provider downloads are unavailable, document the exact command failure and the follow-up command needed once network access is available.

### Review Findings

- [x] [Review][Patch] Explicit system-account access tokens are not stored in Vault [terraform/konnect/main.tf:301]
- [x] [Review][Patch] OIDC client secrets are accepted from committed org YAML before `sensitive_vars` fallback [terraform/konnect/main.tf:579]
- [x] [Review][Patch] Production S3 backend encryption is disabled for the shared state bucket [terraform/konnect/config.s3.tfbackend:11]
- [x] [Review][Patch] API and API Product role resolution can pass names or API IDs instead of the intended entity IDs [terraform/konnect/main.tf:174]
- [x] [Review][Patch] Generated system-account token expiry uses `timestamp()` and drifts on every plan [terraform/konnect/modules/team_system_account/main.tf:12]
- [x] [Review][Patch] Sanitized team names can collide across distinct teams and remote resources [terraform/konnect/main.tf:37]
- [x] [Review][Patch] Multi-file YAML loading uses shallow `merge()` and can drop earlier top-level lists [terraform/konnect/main.tf:4]
- [x] [Review][Patch] Unsupported plugin declarations are silently ignored by the fixed plugin allowlist [terraform/konnect/modules/control_plane/plugins_global.tf:1]
- [x] [Review][Patch] Custom plugin entries require `lua_schema_file` even for config-only instances [terraform/konnect/modules/control_plane/custom_plugins.tf:7]
- [x] [Review][Patch] Standalone route keys can collide with nested service route keys [terraform/konnect/modules/control_plane/services.tf:24]
- [x] [Review][Patch] Service and route OpenTelemetry plugin configs skip the normalization used globally [terraform/konnect/modules/control_plane/plugins_service.tf:14]
- [x] [Review][Patch] Vault placeholder substitution fails open and only replaces top-level values [terraform/konnect/modules/control_plane/vaults.tf:8]
- [x] [Review][Patch] Gateway vault config changes are permanently ignored after creation [terraform/konnect/modules/control_plane/vaults.tf:32]
- [x] [Review][Patch] API version, document, and publication keys cannot represent normal versioned API cases [terraform/konnect/main.tf:521]
- [x] [Review][Patch] API publications can be managed through two independent Terraform paths [terraform/konnect/modules/api/main.tf:23]
- [x] [Review][Patch] Identity provider group mappings can fall back to the first provider instead of failing [terraform/konnect/main.tf:597]
- [x] [Review][Patch] Portal customization and auth inputs are accepted but ignored by module wiring [terraform/konnect/main.tf:395]
- [x] [Review][Patch] Upstream target resources are keyed by list index and churn on reorder [terraform/konnect/modules/control_plane/upstreams.tf:23]

## Dev Notes

### Source Context

- This story comes from the 2026-05-21 sprint change proposal that cancelled the old Epic 3/4/5 scope and replaced it with a unified provisioning engine. [Source: `_bmad-output/planning-artifacts/sprint-change-proposal-2026-05-21.md#Section 1: Issue Summary`]
- Epic 3 requires one workflow, one Terraform root, one Sanofi-style source tree, and one org-level state key. Story 3.1 is only the Terraform-root/module foundation; Story 3.2 migrates YAML, Story 3.3 creates the workflow, and Story 3.4 retires legacy paths. [Source: `_bmad-output/planning-artifacts/epics.md#Epic 3: Unified Konnect Provisioning Engine`]
- ADR #002 is the canonical architecture for this story. The unified root reads all supported resource declarations from `konnect/orgs/<org>/*.yaml`, manages state under `konnect/orgs/<org>/terraform.tfstate`, and preserves HashiCorp Vault integration. [Source: `_bmad-output/planning-artifacts/architecture.md#ADR #002: Unified Konnect Provisioning Engine`]

### Current State To Preserve

- `terraform/konnect/` does not exist yet. Create it additively.
- `terraform/konnect-teams/main.tf` currently provisions teams, team system accounts, Vault mounts/policies, and optional per-team buckets. Story 3.1 should reuse its system-account and Vault patterns, but must not carry forward per-team state buckets into the unified root.
- `.github/actions/provision-konnect-resources/terraform/main.tf` currently parses type-tagged `resources` from one config file and dispatches to many modules. Story 3.1 should reuse/wrap those modules, but the new root must use Sanofi-style top-level keys under `konnect/orgs/<org>/`.
- `konnect/orgs/konnect/*.yaml` already exists but is only partially aligned: `teams.yaml` still uses legacy `control_plane_roles` / `api_roles`, while Sanofi-style target roles use `roles` with `name`, `entity_type_name`, and optional `entity_names`. Full YAML migration belongs to Story 3.2; this module should be ready for that shape.
- Legacy paths remain production-relevant until Story 3.4 verifies parity: `.github/workflows/onboard-konnect-teams.yaml`, `.github/workflows/provision-auth-identity.yaml`, `.github/workflows/provision-konnect-team-resources.yaml`, `terraform/konnect-teams/`, `teams/`, `konnect/auth-identity/`, and `konnect/teams/`.

### Architecture Compliance

- Follow project Terraform conventions: exact provider pins, `for_each` over `count`, stable keys by name/composite ID, `lookup(map, "key", default)` for optional YAML fields, and `terraform plan -out=tfplan` before any apply path. [Source: `_bmad-output/project-context.md#Terraform / HCL`]
- Follow backend pattern P1: committed `config.<backend>.tfbackend` files, selected with `TF_BACKEND_CONFIG`, and init via `terraform init -reconfigure -backend-config="$TF_BACKEND_CONFIG"`. [Source: `_bmad-output/planning-artifacts/architecture.md#P1 — Backend-config file naming and selection`]
- The unified root must use one shared bucket with org-level key `konnect/orgs/<org>/terraform.tfstate`. Do not create or require buckets named `kw.konnect.team.resources.<team>`. [Source: `_bmad-output/planning-artifacts/architecture.md#ADR #002: Unified Konnect Provisioning Engine`]
- HashiCorp Vault is the sole secrets backend for this repo. Local default is docker-compose Vault at `http://localhost:8300`; production swaps `VAULT_ADDR` and `VAULT_TOKEN`. Konnect Config Store and Sanofi's AWS Secrets Manager token storage are out of scope for system-account token persistence. [Source: `_bmad-output/planning-artifacts/architecture.md#ADR #001 — HashiCorp Vault retained; Konnect Config Store deferred`]

### Library / Framework Requirements

- Current repo files inspected during story creation pin `kong/konnect = 3.17.0` in both existing Terraform roots, while planning docs still say `3.15` and Terraform Registry search on 2026-05-21 reported `3.16.0` as latest. Before copying a provider block, verify the real installable version with `terraform init` or the Terraform Registry, then make `terraform/konnect/providers.tf` consistent with the repo's chosen pin. Do not introduce a casual provider upgrade as part of this story.
- Keep `konnect-beta` only where current modules still require it. The dashboard module currently uses `konnect-beta`; preserve that provider mapping if the module is reused.
- Kong's current Terraform docs describe the official Konnect provider as covering control planes, gateway entities, Dev Portal, teams, and more, and note that beta features may start in `konnect-beta`. Use official docs/registry when validating provider coverage. [Source: `https://developer.konghq.com/terraform/`]

### File Structure Requirements

Expected new structure:

```text
terraform/konnect/
  backend.tf
  providers.tf
  variables.tf
  outputs.tf
  main.tf
  config.minio.tfbackend
  config.s3.tfbackend
  modules/
    ...
```

Reference and reuse sources:

- Sanofi reference root: `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/terraform/main.tf`
- Sanofi reference modules: `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/terraform/modules/`
- Sanofi reference YAML: `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/konnect/orgs/sanofi/*.yaml`
- Existing broad module library: `.github/actions/provision-konnect-resources/terraform/modules/`
- Existing Vault/system-account behavior: `terraform/konnect-teams/modules/system-account/` and `terraform/konnect-teams/modules/vault/`

### Testing Requirements

- Minimum required checks for this story:
  - `terraform fmt -check -recursive` from `terraform/konnect/`
  - `terraform init -backend=false` from `terraform/konnect/`
  - `terraform validate` from `terraform/konnect/`
- Do not require a live Konnect token, Vault token, MinIO bucket, or `act` workflow run for Story 3.1. Those are later-story verification gates.
- Validation gates must fail normally. Do not add `continue-on-error: true`, `|| true`, or equivalent bypasses around validation or plan steps. [Source: `_bmad-output/project-context.md#Testing & Validation Rules`]

### Git Intelligence Summary

- Recent commit `e965e9e` added the sprint change proposal and introduced current `konnect/orgs/konnect/*.yaml` plus new auth/identity and Vault-related modules under the old action Terraform tree. Treat that work as the immediate precursor.
- Recent commit `774e502` migrated team roles toward structured API/control-plane role assignments and added state migrations for `for_each` stability. Preserve stable keys and avoid count-indexed resources.
- Recent commit `e9c1f8e` made per-team S3 buckets force-destroyable. Story 3.1 should not carry that behavior forward because ADR #002 removes per-team state buckets from the unified engine.

### Anti-Patterns To Avoid

- Do not build a second type-tagged parser under `terraform/konnect/`; the target model is top-level Sanofi-style YAML keys.
- Do not make Story 3.1 retire workflows or delete legacy Terraform directories. That is Story 3.4 after end-to-end verification.
- Do not echo `KONNECT_TOKEN`, `VAULT_TOKEN`, system-account access tokens, OIDC client secrets, or any `sensitive_vars` values.
- Do not copy Sanofi comments, customer names, internal endpoints, or observability-specific plugin defaults into this repo's committed examples. The repo must remain fictional/customer-neutral.
- Do not use `latest`, `~>`, or unbounded constraints for the Konnect provider in the new root.

### Project Context Reference

- Core agent rules and project conventions are in `_bmad-output/project-context.md`. Read that file before implementation and follow it over generic Terraform/GitHub Actions advice.
- No UX artifact exists for this project. This is a platform-engineering repo, and Story 3.1 has no frontend or operator-UI work.

### Story Completion Status

Ultimate context engine analysis completed - comprehensive developer guide created.

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- 2026-05-21: `terraform init -backend=false` first failed in the default sandbox because DNS resolution for `registry.terraform.io` was unavailable; reran with approved network access and provider install succeeded.
- 2026-05-21: Verified the repo's existing `kong/konnect = 3.17.0` pin is installable via `terraform init -backend=false`.
- 2026-05-21: `terraform validate` first failed in the default sandbox because downloaded provider plugins could not be executed for schema loading; reran with approved execution and validation passed.
- 2026-05-21: Final checks passed from `terraform/konnect/`: `terraform fmt -check -recursive`, `terraform init -backend=false`, and `terraform validate`.

### Completion Notes List

- Created additive unified Terraform root under `terraform/konnect/` with P1 backend config files and default org-level state key `konnect/orgs/konnect/terraform.tfstate`.
- Implemented Sanofi-style top-level YAML loading from `konnect/orgs/<org>/*.yaml` using `fileset()` + `yamldecode()` + `merge()` and defaulted supported top-level keys through locals.
- Copied the existing broad Konnect module library into `terraform/konnect/modules/` and wired root support for control planes, teams, team/system-account roles, per-team system-account token storage in Vault, APIs, portals, dashboards, authentication settings, and identity provider mappings.
- Adapted the copied control-plane module with neutral nested gateway coverage for services, routes, upstreams, vaults, partials, custom plugins, global plugins, service plugins, and route plugins; Sanofi AWS Secrets Manager system-account behavior was not copied.
- Preserved `konnect-beta` provider alias mapping for dashboard provisioning and did not modify legacy Terraform roots or provisioning workflows.
- Resolved review findings for explicit system-account token Vault storage, stable token expiry, safer YAML merging, role entity resolution, nested gateway validation, versioned API keying, portal/auth wiring, and committed secret avoidance.

### File List

- `_bmad-output/implementation-artifacts/3-1-build-unified-terraform-module.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `konnect/orgs/konnect/identity-provider.yaml`
- `konnect/orgs/konnect/portals.yaml`
- `terraform/konnect/.terraform.lock.hcl`
- `terraform/konnect/backend.tf`
- `terraform/konnect/config.minio.tfbackend`
- `terraform/konnect/config.s3.tfbackend`
- `terraform/konnect/main.tf`
- `terraform/konnect/modules/api/main.tf`
- `terraform/konnect/modules/api/outputs.tf`
- `terraform/konnect/modules/api/variables.tf`
- `terraform/konnect/modules/api_document/main.tf`
- `terraform/konnect/modules/api_document/variables.tf`
- `terraform/konnect/modules/api_implementation/main.tf`
- `terraform/konnect/modules/api_publication/main.tf`
- `terraform/konnect/modules/api_publication/outputs.tf`
- `terraform/konnect/modules/api_publication/variables.tf`
- `terraform/konnect/modules/api_specification/main.tf`
- `terraform/konnect/modules/api_specification/variables.tf`
- `terraform/konnect/modules/api_version/README.md`
- `terraform/konnect/modules/api_version/main.tf`
- `terraform/konnect/modules/api_version/outputs.tf`
- `terraform/konnect/modules/api_version/variables.tf`
- `terraform/konnect/modules/application_auth_strategy/README.md`
- `terraform/konnect/modules/application_auth_strategy/main.tf`
- `terraform/konnect/modules/application_auth_strategy/outputs.tf`
- `terraform/konnect/modules/application_auth_strategy/variables.tf`
- `terraform/konnect/modules/audit_log/main.tf`
- `terraform/konnect/modules/audit_log/variables.tf`
- `terraform/konnect/modules/audit_log_destination/main.tf`
- `terraform/konnect/modules/audit_log_destination/variables.tf`
- `terraform/konnect/modules/authentication_settings/main.tf`
- `terraform/konnect/modules/authentication_settings/variables.tf`
- `terraform/konnect/modules/centralized_consumer/main.tf`
- `terraform/konnect/modules/centralized_consumer/outputs.tf`
- `terraform/konnect/modules/centralized_consumer/variables.tf`
- `terraform/konnect/modules/centralized_consumer_key/main.tf`
- `terraform/konnect/modules/centralized_consumer_key/outputs.tf`
- `terraform/konnect/modules/centralized_consumer_key/variables.tf`
- `terraform/konnect/modules/cloud_gateway_configuration/main.tf`
- `terraform/konnect/modules/cloud_gateway_configuration/variables.tf`
- `terraform/konnect/modules/cloud_gateway_custom_domain/main.tf`
- `terraform/konnect/modules/cloud_gateway_custom_domain/outputs.tf`
- `terraform/konnect/modules/cloud_gateway_custom_domain/variables.tf`
- `terraform/konnect/modules/cloud_gateway_network/main.tf`
- `terraform/konnect/modules/cloud_gateway_network/variables.tf`
- `terraform/konnect/modules/cloud_gateway_private_dns/main.tf`
- `terraform/konnect/modules/cloud_gateway_private_dns/variables.tf`
- `terraform/konnect/modules/cloud_gateway_transit_gateway/main.tf`
- `terraform/konnect/modules/cloud_gateway_transit_gateway/variables.tf`
- `terraform/konnect/modules/control_plane/custom_plugins.tf`
- `terraform/konnect/modules/control_plane/main.tf`
- `terraform/konnect/modules/control_plane/partials.tf`
- `terraform/konnect/modules/control_plane/plugins_global.tf`
- `terraform/konnect/modules/control_plane/plugins_route.tf`
- `terraform/konnect/modules/control_plane/plugins_service.tf`
- `terraform/konnect/modules/control_plane/services.tf`
- `terraform/konnect/modules/control_plane/upstreams.tf`
- `terraform/konnect/modules/control_plane/variables.tf`
- `terraform/konnect/modules/control_plane/vaults.tf`
- `terraform/konnect/modules/dashboard/main.tf`
- `terraform/konnect/modules/dashboard/outputs.tf`
- `terraform/konnect/modules/dashboard/variables.tf`
- `terraform/konnect/modules/developer_portal/README.md`
- `terraform/konnect/modules/developer_portal/main.tf`
- `terraform/konnect/modules/developer_portal/outputs.tf`
- `terraform/konnect/modules/developer_portal/variables.tf`
- `terraform/konnect/modules/identity_provider/main.tf`
- `terraform/konnect/modules/identity_provider/outputs.tf`
- `terraform/konnect/modules/identity_provider/variables.tf`
- `terraform/konnect/modules/identity_provider_team_group_mapping/main.tf`
- `terraform/konnect/modules/identity_provider_team_group_mapping/variables.tf`
- `terraform/konnect/modules/integration_instance/main.tf`
- `terraform/konnect/modules/integration_instance/outputs.tf`
- `terraform/konnect/modules/integration_instance/variables.tf`
- `terraform/konnect/modules/integration_instance_auth_config/main.tf`
- `terraform/konnect/modules/integration_instance_auth_config/variables.tf`
- `terraform/konnect/modules/integration_instance_auth_credential/main.tf`
- `terraform/konnect/modules/integration_instance_auth_credential/variables.tf`
- `terraform/konnect/modules/portal_appearance/main.tf`
- `terraform/konnect/modules/portal_appearance/outputs.tf`
- `terraform/konnect/modules/portal_appearance/variables.tf`
- `terraform/konnect/modules/portal_auth/main.tf`
- `terraform/konnect/modules/portal_auth/variables.tf`
- `terraform/konnect/modules/portal_custom_domain/main.tf`
- `terraform/konnect/modules/portal_custom_domain/variables.tf`
- `terraform/konnect/modules/portal_customization/main.tf`
- `terraform/konnect/modules/portal_customization/outputs.tf`
- `terraform/konnect/modules/portal_customization/variables.tf`
- `terraform/konnect/modules/portal_favicon/main.tf`
- `terraform/konnect/modules/portal_favicon/outputs.tf`
- `terraform/konnect/modules/portal_favicon/variables.tf`
- `terraform/konnect/modules/portal_logo/main.tf`
- `terraform/konnect/modules/portal_logo/outputs.tf`
- `terraform/konnect/modules/portal_logo/variables.tf`
- `terraform/konnect/modules/portal_page/main.tf`
- `terraform/konnect/modules/portal_page/outputs.tf`
- `terraform/konnect/modules/portal_page/variables.tf`
- `terraform/konnect/modules/portal_product_version/main.tf`
- `terraform/konnect/modules/portal_product_version/outputs.tf`
- `terraform/konnect/modules/portal_product_version/variables.tf`
- `terraform/konnect/modules/portal_snippet/main.tf`
- `terraform/konnect/modules/portal_snippet/outputs.tf`
- `terraform/konnect/modules/portal_snippet/variables.tf`
- `terraform/konnect/modules/portal_team/main.tf`
- `terraform/konnect/modules/portal_team/variables.tf`
- `terraform/konnect/modules/realm/main.tf`
- `terraform/konnect/modules/realm/outputs.tf`
- `terraform/konnect/modules/realm/variables.tf`
- `terraform/konnect/modules/system_account/main.tf`
- `terraform/konnect/modules/system_account/outputs.tf`
- `terraform/konnect/modules/system_account/variables.tf`
- `terraform/konnect/modules/system_account_access_token/main.tf`
- `terraform/konnect/modules/system_account_access_token/outputs.tf`
- `terraform/konnect/modules/system_account_access_token/variables.tf`
- `terraform/konnect/modules/system_account_role/main.tf`
- `terraform/konnect/modules/system_account_role/outputs.tf`
- `terraform/konnect/modules/system_account_role/variables.tf`
- `terraform/konnect/modules/system_account_team/main.tf`
- `terraform/konnect/modules/system_account_team/outputs.tf`
- `terraform/konnect/modules/system_account_team/variables.tf`
- `terraform/konnect/modules/team/main.tf`
- `terraform/konnect/modules/team/outputs.tf`
- `terraform/konnect/modules/team/variables.tf`
- `terraform/konnect/modules/team_role/main.tf`
- `terraform/konnect/modules/team_role/outputs.tf`
- `terraform/konnect/modules/team_role/variables.tf`
- `terraform/konnect/modules/team_system_account/main.tf`
- `terraform/konnect/modules/team_system_account/variables.tf`
- `terraform/konnect/modules/team_user/main.tf`
- `terraform/konnect/modules/team_user/outputs.tf`
- `terraform/konnect/modules/team_user/variables.tf`
- `terraform/konnect/modules/team_vault/main.tf`
- `terraform/konnect/modules/team_vault/variables.tf`
- `terraform/konnect/outputs.tf`
- `terraform/konnect/providers.tf`
- `terraform/konnect/variables.tf`

### Change Log

- 2026-05-21: Implemented unified `terraform/konnect/` root, copied/wrapped reusable Konnect modules, adapted nested control-plane gateway coverage, preserved Vault token storage, and validated the new root.
- 2026-05-21: Applied code review fixes and revalidated `terraform/konnect/`; story moved to done.
