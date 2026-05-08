# Konnect Provider 3.1.0 → 3.15.0 Schema-Diff Audit

> Story 1.1 deliverable. Source of truth for Stories 1.2 (outer tree HCL edits), 1.3 (inner tree HCL edits), 1.4 (state-migration scripts), and 1.6 (`MIGRATION.md` §2 / clean-plan verification).

> Provider source: `/Users/jordi.fernandez/github/terraform-provider-konnect` (CHANGELOG `## 3.1.0` → `## 3.15.0`, 2025-09-02 → 2026-05-05). Both consuming Terraform trees pin `kong/konnect = 3.1.0` exact.

## Summary

The repository declares **41 distinct `konnect_*` resource types** across two Terraform root modules and uses **zero `data "konnect_*"` data sources** (the only `data` blocks are `terracurl_request` against `global.api.konghq.com`). Five resource types appear in the outer tree (`terraform/konnect-teams/`) and 41 in the inner tree (`.github/actions/provision-konnect-resources/terraform/`), with `konnect_team`, `konnect_system_account`, `konnect_system_account_team`, `konnect_system_account_role`, and `konnect_system_account_access_token` overlapping between trees.

**Out-of-scope items noted but not classified:**
- `terraform/konnect-teams/modules/vault/` uses `vault_*` provider resources only (the architecture-doc D3 reference to the Vault module is informational).
- `.github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf:71` declares `vault_kv_secret_v2 "this"`. The inner-tree `providers.tf` does not pin a `vault` provider — a pre-existing latent issue surfaced by this audit but **not** introduced by the 3.1.0 → 3.15.0 bump. Flag for a future audit pass.
- `konnect_dashboard` is provisioned by `Kong/konnect-beta = 0.11.1`, not `kong/konnect`. It is listed in the inventory for completeness but **excluded from AC4 classification counts** below (the kong/konnect bump does not interact with it).

Classification counts (AC4) — over the **40 in-scope `kong/konnect` resource types** (41 distinct types minus the out-of-scope `konnect_dashboard`):
- `no-change` — **39 resource types** (every type the repo writes today still validates against the 3.15 schema with the same attribute set).
- `attribute-edit-required` — **0** resource types.
- `state-mv-required` — **0** resource types.
- `deprecation-flagged` — **1** resource type (`konnect_portal_auth`; the OIDC/SAML/IDP properties the repo wires from YAML at root `main.tf:281-297` were deprecated in 3.4.3 in favor of the Identity Provider API. Note: the 3.4.3 deprecation also covers `oidc_claim_mappings`, which the module exposes but the root wiring does **not** pass through — see the `konnect_portal_auth` per-resource section).

State-migration operation count (AC3): **0**. The only historical candidate (`konnect_portal` v2 → v3 import-into-`konnect_portal_classic`) was a 3.0.0 BREAKING change and is already past the 3.1.0 baseline; the 3.1.0 → 3.15.0 hop is purely additive for every resource type the repo uses. Story 1.4's `001-konnect-3-15-rename.sh` scripts are still required to land the standard header/marker convention, but their bodies remain idempotent no-ops with explanatory comments rather than actual `terraform state mv` invocations.

Behavior changes worth flagging for Story 1.6 ("zero `terraform plan` diffs after init -upgrade"). The repo's baseline is **3.1.0 exact**, so 3.1.0's own changes are *baseline state* and not part of the bump-effect set; the items below land **after** 3.1.0 and may shift `plan` output without HCL edits:
- `konnect_cloud_gateway_configuration` — false-diff fix in 3.2.0; `max_rps` made read-only with a separate plan fix in 3.6.0.
- `konnect_portal_customization` — `theme` / `menu` can now be unset (3.2.1).
- `konnect_system_account_access_token` — false-diff fix on plan output (3.2.1).
- `konnect_portal_auth` — drift-detection fix (3.6.0).
- 3.4.0 fixed "unnecessary planned changes seen in child resources when the parent was updated." The CHANGELOG does not name a specific resource, so the affected surface in this repo cannot be enumerated up-front; Story 1.6 should observe `plan` output against the dummy-fixture / MinIO local backend and treat any unexpected child-resource churn as the suspect.

(Note: the `konnect_api` 3.1.0 false-diff fix is **inside** the 3.1.0 baseline and is therefore already realized in current plan output — not a bump-effect.)

## Resource inventory by tree

### `terraform/konnect-teams/` (outer tree)

| Resource Type | Files (path:line) | Count |
| --- | --- | --- |
| `konnect_team` | `terraform/konnect-teams/main.tf:24` | 1 |
| `konnect_system_account` | `terraform/konnect-teams/modules/system-account/main.tf:15` | 1 |
| `konnect_system_account_team` | `terraform/konnect-teams/modules/system-account/main.tf:24` | 1 |
| `konnect_system_account_role` | `terraform/konnect-teams/modules/system-account/main.tf:31`, `:42`, `:53`, `:64`, `:75`, `:86`, `:97`, `:108` | 8 (each `count`-guarded by entitlement) |
| `konnect_system_account_access_token` | `terraform/konnect-teams/modules/system-account/main.tf:119` | 1 |

`terraform/konnect-teams/modules/vault/` uses `vault_kv_secret_v2` from the `hashicorp/vault` provider only — **no `konnect_*` declarations**, so it does not participate in the kong/konnect bump. (Note: a second `vault_kv_secret_v2` is also declared in the inner tree at `.github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf:71`; the inner tree's `providers.tf` does not pin a `vault` provider, which is a pre-existing latent bug noted in the Summary as out-of-scope for the kong/konnect bump.)

### `.github/actions/provision-konnect-resources/terraform/` (inner tree)

| Resource Type | Files (path:line) | Count |
| --- | --- | --- |
| `konnect_api` | `modules/api/main.tf:10` | 1 |
| `konnect_api_document` | `modules/api_document/main.tf:10` | 1 |
| `konnect_api_implementation` | `modules/api_implementation/main.tf:10` | 1 (module body commented out in root `main.tf:692-702`) |
| `konnect_api_publication` | `modules/api/main.tf:23`, `modules/api_publication/main.tf:10` | 2 |
| `konnect_api_specification` | `modules/api_specification/main.tf:10` | 1 (module body commented out in root `main.tf:682-690`) |
| `konnect_api_version` | `modules/api_version/main.tf:10` | 1 |
| `konnect_application_auth_strategy` | `modules/application_auth_strategy/main.tf:10` | 1 |
| `konnect_audit_log` | `modules/audit_log/main.tf:10` | 1 |
| `konnect_audit_log_destination` | `modules/audit_log_destination/main.tf:10` | 1 |
| `konnect_centralized_consumer` | `modules/centralized_consumer/main.tf:10` | 1 |
| `konnect_centralized_consumer_key` | `modules/centralized_consumer_key/main.tf:10` | 1 |
| `konnect_cloud_gateway_configuration` | `modules/cloud_gateway_configuration/main.tf:9` | 1 |
| `konnect_cloud_gateway_custom_domain` | `modules/cloud_gateway_custom_domain/main.tf:10` | 1 |
| `konnect_cloud_gateway_network` | `modules/cloud_gateway_network/main.tf:9` | 1 |
| `konnect_cloud_gateway_private_dns` | `modules/cloud_gateway_private_dns/main.tf:52` | 1 |
| `konnect_cloud_gateway_transit_gateway` | `modules/cloud_gateway_transit_gateway/main.tf:10` | 1 |
| `konnect_dashboard` | `modules/dashboard/main.tf:10` | 1 (uses **`Kong/konnect-beta = 0.11.1`** provider — outside this bump's scope) |
| `konnect_gateway_control_plane` | `modules/control_plane/main.tf:10` | 1 |
| `konnect_gateway_data_plane_client_certificate` | `modules/control_plane/main.tf:63` | 1 |
| `konnect_integration_instance` | `modules/integration_instance/main.tf:10` | 1 |
| `konnect_integration_instance_auth_config` | `modules/integration_instance_auth_config/main.tf:10` | 1 |
| `konnect_integration_instance_auth_credential` | `modules/integration_instance_auth_credential/main.tf:10` | 1 |
| `konnect_portal` | `modules/developer_portal/main.tf:10` | 1 |
| `konnect_portal_appearance` | `modules/portal_appearance/main.tf:10` | 1 |
| `konnect_portal_auth` | `modules/portal_auth/main.tf:10` | 1 |
| `konnect_portal_custom_domain` | `modules/portal_custom_domain/main.tf:10` | 1 |
| `konnect_portal_customization` | `modules/portal_customization/main.tf:10` | 1 |
| `konnect_portal_favicon` | `modules/portal_favicon/main.tf:10` | 1 |
| `konnect_portal_logo` | `modules/portal_logo/main.tf:10` | 1 |
| `konnect_portal_page` | `modules/portal_page/main.tf:10` | 1 |
| `konnect_portal_product_version` | `modules/portal_product_version/main.tf:10` | 1 |
| `konnect_portal_snippet` | `modules/portal_snippet/main.tf:10` | 1 |
| `konnect_portal_team` | `modules/portal_team/main.tf:10` | 1 |
| `konnect_realm` | `modules/realm/main.tf:10` | 1 |
| `konnect_system_account` | `modules/system_account/main.tf:10` | 1 |
| `konnect_system_account_access_token` | `modules/system_account_access_token/main.tf:15` | 1 |
| `konnect_system_account_role` | `modules/system_account_role/main.tf:10` | 1 |
| `konnect_system_account_team` | `modules/system_account_team/main.tf:10` | 1 |
| `konnect_team` | `modules/team/main.tf:10` | 1 |
| `konnect_team_role` | `modules/team_role/main.tf:10` | 1 |
| `konnect_team_user` | `modules/team_user/main.tf:10` | 1 |

The inner tree's root `providers.tf` also pins `devops-rob/terracurl = 1.0.1`, plus `tls` and `time` providers consumed inside `modules/control_plane/`. None are `konnect_*` resources and none are affected by the bump.

## Per-resource schema diff

For each entry below: classification (AC4) → attributes the repo writes today → schema changes 3.1.0 → 3.15.0 affecting those attributes → citations.

**AC2 five-category convention.** Where a per-resource section does not enumerate the AC2 categories explicitly, the implicit attestation — verified by reading the resource's `docs/resources/<name>.md` `## Schema` section against the 3.1.0 baseline schema — is: **Added required: none. Renamed: none. Removed: none. Newly deprecated: none. Changed type or default: none.** Resources where this implicit no-op fails (additive optionals, deprecations, read-only changes) call out the relevant category by name in their entry below.

### `konnect_api`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `description`, `labels`, `slug`, `spec_content`, `version`.
- **3.1.0 → 3.15.0:** No required-attribute additions, no renames, no removals. The 3.1.0 false-diff fix on `konnect_api` is inside the baseline and is **not** a bump-effect.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/api.md#Schema] (3.15 contract: only `name` is Required; `description`, `labels`, `slug`, `spec_content`, `version` Optional). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/api/main.tf:10-21].

### `konnect_api_document`

- **Classification:** `no-change`.
- **Attributes used:** `api_id`, `content`, `parent_document_id`, `slug`, `status`, `title`.
- **3.1.0 → 3.15.0:** Resource was introduced in 3.0.0; no schema changes between 3.1.0 and 3.15.0 named in CHANGELOG.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/api_document.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.0.0] (introduces `konnect_api_document`). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/api_document/main.tf:10].

### `konnect_api_implementation`

- **Classification:** `no-change`.
- **Attributes used:** `api_id`, `service.control_plane_id`, `service.id` (per the dormant module body — the calling module block is commented out in root `main.tf` and currently produces no plan).
- **3.1.0 → 3.15.0:** 3.7.0 added "support linking APIs to Control Planes using `konnect_api_implementation`" — additive feature behind the same attribute shape; no required-attribute change.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.7.0]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/api_implementation.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/api_implementation/main.tf:10]; module call commented out at [Source: .github/actions/provision-konnect-resources/terraform/main.tf:692-702].

### `konnect_api_publication`

- **Classification:** `no-change`.
- **Attributes used (two declaration paths with different attribute coverage):**
  - `modules/api/main.tf:23-31` (in-line publication created alongside `konnect_api`): only `api_id`, `portal_id`, `visibility`. `auth_strategy_ids` and `auto_approve_registrations` are **not** set (they default to `null`).
  - `modules/api_publication/main.tf:10` (standalone publication module): `api_id`, `portal_id`, `auth_strategy_ids`, `auto_approve_registrations`, `visibility`.
  - The two paths produce publications with different attribute defaults; Story 1.6's clean-plan gate must exercise both.
- **3.1.0 → 3.15.0:** Resource introduced in 3.0.0; no schema changes between 3.1.0 and 3.15.0 named in CHANGELOG.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/api_publication.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.0.0]. Repo declarations at [Source: .github/actions/provision-konnect-resources/terraform/modules/api/main.tf:23-31] and [Source: .github/actions/provision-konnect-resources/terraform/modules/api_publication/main.tf:10].

### `konnect_api_specification`

- **Classification:** `no-change`.
- **Attributes used:** `api_id`, `content`, `type` (per the dormant module body — calling module commented out in root `main.tf`).
- **3.1.0 → 3.15.0:** Resource introduced in 3.0.0; no relevant changes.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/api_specification.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.0.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/api_specification/main.tf:10]; call commented out at [Source: .github/actions/provision-konnect-resources/terraform/main.tf:682-690].

### `konnect_api_version`

- **Classification:** `no-change`.
- **Attributes used:** `api_id`, `version`, `spec_content`.
- **3.1.0 → 3.15.0:** Resource introduced in 3.0.0; no relevant changes.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/api_version.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.0.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/api_version/main.tf:10].

### `konnect_application_auth_strategy`

- **Classification:** `no-change`.
- **Attributes used:** Either the `key_auth` block (with `display_name`, `labels`, `name`, `strategy_type = "key_auth"`, `configs.key_auth.key_names`) or the `openid_connect` block (with `display_name`, `labels`, `name`, `strategy_type = "openid_connect"`, `dcr_provider_id`, `configs.openid_connect.{additional_properties, auth_methods, credential_claim, issuer, scopes}`). The repo branches via `var.strategy_type`.
- **3.1.0 → 3.15.0:** 3.8.0 fixed provisioning of key-auth strategies by treating `configs.ttl` as non-nullable — behavior fix only; the repo never sets `configs.key_auth.ttl`, so this is a non-event for current usage.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/application_auth_strategy.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.8.0] ("Fix provisioning key-auth `konnect_application_auth_strategy` by treating `configs.ttl` as non-nullable"). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/application_auth_strategy/main.tf:10-39].

### `konnect_audit_log`

- **Classification:** `no-change`.
- **Attributes used:** `endpoint`, `authorization`, `enabled`, `log_format`, `skip_ssl_verification`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/audit_log.md#Schema] (all attributes Optional in 3.15). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/audit_log/main.tf:10-16].

### `konnect_audit_log_destination`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `endpoint`, `authorization`, `log_format`, `skip_ssl_verification`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource. 3.15 schema marks `name`, `endpoint`, and `authorization` as Required — the repo's main.tf-level invocation passes all three from YAML (with `authorization = lookup(..., null)`); operators must continue to provide a non-null `authorization` in YAML, but this matches 3.1.0 behavior.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/audit_log_destination.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/audit_log_destination/main.tf:10].

### `konnect_centralized_consumer`

- **Classification:** `no-change`.
- **Attributes used:** `realm_id`, `username`, `custom_id`, `type` (mapped from YAML field `consumer_type` via the module variable name), `consumer_groups`, `tags`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/centralized_consumer.md#Schema] (`realm_id`, `username` Required; `type` defaults to "proxy"). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/centralized_consumer/main.tf:10-18].

### `konnect_centralized_consumer_key`

- **Classification:** `no-change`.
- **Attributes used:** `realm_id`, `consumer_id`, `type` (mapped from YAML `key_type`), `secret`, `tags`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/centralized_consumer_key.md#Schema] (`realm_id`, `consumer_id` Required; `type` Optional default "legacy"). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/centralized_consumer_key/main.tf:10-17].

### `konnect_cloud_gateway_configuration`

- **Classification:** `no-change` (with watchpoint).
- **Attributes used:** `control_plane_id`, `control_plane_geo`, `dataplane_groups` (passed through verbatim from YAML), `version`.
- **3.1.0 → 3.15.0:**
  - 3.2.0: false-diff fix on `terraform plan` (behavior-only).
  - 3.6.0: `max_rps` is now treated as **read-only**, *and* false-diff fix on `terraform plan`. **This only breaks operators who set `dataplane_groups[*].autoscale.configuration_data_plane_group_autoscale_autopilot.max_rps` directly.** Verification grep — `grep -rn 'max_rps' --include='*.tf' --include='*.yaml' --include='*.yml' .` from the repo root — returns **zero hits** in operator-supplied HCL or YAML on commit `2f8ce14` (2026-05-08). The only repo-wide `max_rps` mentions are in the bundled provider `schema.json` (a generated cache of the provider schema) and in this story's own files. No HCL edit needed; flag for Story 1.6's clean-plan verification.
  - 3.6.0 / 3.8.0 / 3.11.0 / 3.15.0: additive features (serverless EA, GCP provider, managed cache add-ons, larger capacity tiers). All Optional, none of which the repo currently uses.
- **Watchpoint for Story 1.6:** When YAML-authored cloud-gateway configurations land for new operators, the validator scripts under `.github/actions/provision-konnect-resources/scripts/` should reject any `max_rps` field nested under autopilot autoscale to keep the `attribute-edit-required` classification at zero.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/cloud_gateway_configuration.md#Schema] (3.15 contract; `max_rps` shown as `Number, Deprecated, Read-Only` under `dataplane_groups.autoscale.configuration_data_plane_group_autoscale_autopilot`). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.6.0] ("Treat `max_rps` as read only property to fix updates in `konnect_cloud_gateway_configuration` resource"). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.2.0] (false-diff fix). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_configuration/main.tf:9-14].

### `konnect_cloud_gateway_custom_domain`

- **Classification:** `no-change`.
- **Attributes used:** `control_plane_id`, `control_plane_geo`, `domain`.
- **3.1.0 → 3.15.0:** 3.12.0 added `kind = "serverless.v1"` support — additive Optional attribute; the repo does not set `kind`.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/cloud_gateway_custom_domain.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.12.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_custom_domain/main.tf:10].

### `konnect_cloud_gateway_network`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `region`, `cidr_block`, `availability_zones`, `cloud_gateway_provider_account_id`.
- **3.1.0 → 3.15.0:** 3.6.0 added `azure_private_dns_resolver` support — additive Optional. 3.14.0 added `konnect_cloud_gateway_network` data source — also additive.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/cloud_gateway_network.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.6.0]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.14.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_network/main.tf:9].

### `konnect_cloud_gateway_private_dns`

- **Classification:** `no-change` (with watchpoint).
- **Attributes used:** `network_id`, `name`, `private_dns_attachment_config`.
- **3.1.0 → 3.15.0:** 3.2.0 added GCP Private Hosted Zone, 3.8.0 added Azure Private Hosted Zone, 3.9.0 added Azure Private DNS — all additive Optional sub-blocks under `private_dns_attachment_config` at the **provider** level.
- **Watchpoint:** the repo's module wrapper (`modules/cloud_gateway_private_dns/main.tf:36-49` `normalized_attachment` local) only re-emits `aws_private_dns_resolver_attachment_config` and `aws_private_hosted_zone_attachment_config`. Any GCP or Azure attachment config supplied via YAML is silently dropped before reaching the resource. Adopting the GCP/Azure additive features therefore requires an HCL change to this module — *not* a pure 3.15 schema upgrade. Note for Stories 1.3 / 1.6.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/cloud_gateway_private_dns.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.2.0], [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.8.0], [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.9.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_private_dns/main.tf:52]; AWS-only normalization at [Source: .github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_private_dns/main.tf:36-49].

### `konnect_cloud_gateway_transit_gateway`

- **Classification:** `no-change`.
- **Attributes used:** `network_id`, plus exactly one of `aws_transit_gateway`, `aws_vpc_peering_gateway`, `azure_transit_gateway`, `gcp_vpc_peering_transit_gateway` (all Optional).
- **3.1.0 → 3.15.0:** 3.0.0 introduced `gcp_vpc_peering_transit_gateway` (already inside the 3.1.0 baseline). 3.2.0 added `aws_resource_endpoint_gateway`. 3.5.0 added PATCH update support without replacement. All additive.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/cloud_gateway_transit_gateway.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.2.0]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.5.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_transit_gateway/main.tf:10].

### `konnect_dashboard`

- **Classification:** **out-of-scope** (provisioned by `Kong/konnect-beta`, not `kong/konnect`). Listed in the inventory for completeness; **not counted** in the AC4 classification totals.
- **Attributes used:** `name`, `labels`, `definition`.
- **3.1.0 → 3.15.0:** The `kong/konnect` 3.1.0 → 3.15.0 bump does not interact with this declaration — `konnect_dashboard` is exclusively provided by `Kong/konnect-beta = 0.11.1`. Story 1.2/1.3 must leave the `konnect-beta` block in `providers.tf` untouched; the konnect-beta 0.11.1 schema diff is **out of scope for Story 1.1** and is not assessed here.
- **Citations:** Provider pin at [Source: .github/actions/provision-konnect-resources/terraform/main.tf:7-10] (`Kong/konnect-beta = 0.11.1`). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/dashboard/main.tf:10].

### `konnect_gateway_control_plane`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `description`, `cloud_gateway`, `cluster_type`, `auth_type`, `labels`.
- **3.1.0 → 3.15.0:** 3.3.0 added `konnect_gateway_control_plane_list` data source (additive; the repo doesn't use it). No required-attribute changes; `proxy_urls` Optional attribute remained Optional.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/gateway_control_plane.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.3.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf:10-19].

### `konnect_gateway_data_plane_client_certificate`

- **Classification:** `no-change`.
- **Attributes used:** `cert`, `control_plane_id`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource between 3.1.0 and 3.15.0.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/gateway_data_plane_client_certificate.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf:63-67].

### `konnect_integration_instance`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `display_name`, `integration_name`, `description`, `config` (jsonencoded).
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/integration_instance.md#Schema] (`config`, `display_name`, `integration_name`, `name` Required; `description`, `labels` Optional — repo passes the four required + `description`). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/integration_instance/main.tf:10].

### `konnect_integration_instance_auth_config`

- **Classification:** `no-change`.
- **Attributes used:** `integration_instance_id`, `oauth_config`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/integration_instance_auth_config.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/integration_instance_auth_config/main.tf:10].

### `konnect_integration_instance_auth_credential`

- **Classification:** `no-change`.
- **Attributes used:** `integration_instance_id`, `multi_key_auth`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/integration_instance_auth_credential.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/integration_instance_auth_credential/main.tf:10].

### `konnect_portal`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `description`, `display_name`, `labels`, `authentication_enabled`, `auto_approve_applications`, `auto_approve_developers`, `default_api_visibility`, `default_application_auth_strategy_id`, `default_page_visibility`, `rbac_enabled`, `force_destroy`.
- **3.1.0 → 3.15.0:**
  - **3.0.0 BREAKING (already past at the 3.1.0 baseline):** the legacy v2 `konnect_portal` had to be imported into `konnect_portal_classic` before adopting v3. Because the repo is already on `kong/konnect = 3.1.0` and uses the v3 schema, no `terraform state mv` or `import` is required for the 3.1.0 → 3.15.0 hop. **Confirmed.**
  - The 3.15 schema exposes a `sipr_enabled` Optional attribute (default `false`) that the repo does not set. The CHANGELOG (3.0.0 → 3.15.0) does not pin a version that introduced it; the audit only verifies it is present in the 3.15 schema doc.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal.md#Schema] (3.15 contract — `sipr_enabled` listed as Optional). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.0.0] (BREAKING note). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#2.14.0] (introduces `konnect_portal_classic`). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/developer_portal/main.tf:10-23].

### `konnect_portal_appearance`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `theme_name`, `use_custom_fonts`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_appearance.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_appearance/main.tf:10].

### `konnect_portal_auth`

- **Classification:** **`deprecation-flagged`**.
- **Attributes wired from YAML (root `main.tf:281-297`):** `portal_id`, `basic_auth_enabled`, `oidc_auth_enabled`, `saml_auth_enabled`, `idp_mapping_enabled`, `konnect_mapping_enabled`, `oidc_team_mapping_enabled`, `oidc_issuer`, `oidc_client_id`, `oidc_client_secret`, `oidc_scopes`. The module variable surface also accepts `oidc_claim_mappings`, but the root wiring does **not** pass it through; an operator setting `oidc_claim_mappings` in YAML today silently no-ops. Worth surfacing if/when the IdP-API migration lands.
- **3.1.0 → 3.15.0:**
  - **3.4.3:** Every IDP / SAML / OIDC property is marked `Deprecated` in the schema in favor of the [Identity Provider API](https://developer.konghq.com/api/konnect/portal-management/v3/#/operations/update-portal-identity-provider). Specifically deprecated: `oidc_auth_enabled`, `saml_auth_enabled`, `oidc_team_mapping_enabled`, `oidc_claim_mappings`, `oidc_client_id`, `oidc_client_secret`, `oidc_issuer`, `oidc_scopes`, plus the read-only `oidc_config` block. `basic_auth_enabled`, `idp_mapping_enabled`, and `konnect_mapping_enabled` are *not* deprecated.
  - **3.6.0:** Drift-detection fix for `konnect_portal_auth` (behavior-only).
  - **No required-attribute additions, no removals.** A 3.15-era `terraform plan -upgrade` against existing state will succeed; deprecation warnings will surface but the resource will continue to apply cleanly.
- **Watchpoint for Story 1.6:** the IdP-API migration is a Konnect-API surface change (not a provider rename) and is **out of scope** for this 3.1.0 → 3.15.0 bump. Story 1.6's `MIGRATION.md` §2 should pin awareness only — *not* attempt the migration. A future deprecation-removal release will require a coordinated rewrite of `modules/portal_auth/` plus the root wiring at `main.tf:281-297` to consume the new resource (likely `konnect_identity_provider` introduced in 3.8.0). The un-wired `oidc_claim_mappings` should also be wired-or-removed during that rewrite.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_auth.md#Schema] (each deprecated attribute is annotated `(Boolean, Deprecated)` / `(String, Deprecated)` / `(Attributes, Deprecated)` with the IdP-API redirect). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.4.3] ("Properties related to IDP, SAML and OIDC are deprecated in `konnect_portal_auth` resource"). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.6.0] ("Fix drift detection in `konnect_portal_auth` resource"). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.8.0] (introduces `konnect_identity_provider`). Repo declarations at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_auth/main.tf:10-26] and [Source: .github/actions/provision-konnect-resources/terraform/main.tf:281-297].

### `konnect_portal_custom_domain`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `hostname`, `enabled`.
- **3.1.0 → 3.15.0:** 3.4.1 added Optional `skip_ca_check`. Additive; repo doesn't set it.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_custom_domain.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.4.1]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_custom_domain/main.tf:10].

### `konnect_portal_customization`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `css`, `layout`, `robots`, `menu`, `spec_renderer`, `theme`.
- **3.1.0 → 3.15.0:** 3.2.1 fixed: `theme` and `menu` can now be unset (set to `null`) without producing a diff. Behavior-only fix — no HCL change required, but `terraform plan` against state created on 3.1.0 with null values for `theme`/`menu` may show clean diffs after the bump that previously appeared dirty. Flag for Story 1.6.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_customization.md#Schema] (only `portal_id` Required). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.2.1] ("Properties such as `theme`, `menu` can now be unset in `konnect_portal_customization` resource"). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_customization/main.tf:10].

### `konnect_portal_favicon`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `data`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_favicon.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_favicon/main.tf:10].

### `konnect_portal_logo`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `data`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_logo.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_logo/main.tf:10].

### `konnect_portal_page`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `slug`, `content`, `title`, `description`, `parent_page_id`, `status`, `visibility`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_page.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_page/main.tf:10].

### `konnect_portal_product_version`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `product_version_id`, `publish_status`, `application_registration_enabled`, `auto_approve_registration`, `deprecated`, `auth_strategy_ids`, `notify_developers`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource. The 3.15 schema continues to require `application_registration_enabled`, `auth_strategy_ids`, `auto_approve_registration`, `deprecated`, `portal_id`, `product_version_id`, and `publish_status` — every one of which the repo passes from YAML without a `lookup(..., null)` fallback, so the validator must continue to require them in operator YAML.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_product_version.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_product_version/main.tf:10] and root invocation at [Source: .github/actions/provision-konnect-resources/terraform/main.tf:375-388].

### `konnect_portal_snippet`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `name`, `content`, `title`, `description`, `status`, `visibility`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_snippet.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_snippet/main.tf:10].

### `konnect_portal_team`

- **Classification:** `no-change`.
- **Attributes used:** `portal_id`, `name`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/portal_team.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/portal_team/main.tf:10].

### `konnect_realm`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `allow_all_control_planes`, `allowed_control_planes`, `consumer_groups`, `ttl`, `negative_ttl`, `force_destroy`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/realm.md#Schema] (only `name` Required). Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/realm/main.tf:10].

### `konnect_system_account`

- **Classification:** `no-change`.
- **Attributes used (outer tree):** `name`, `description`, `konnect_managed`. **(Inner tree):** same — the inner module sets `description = coalesce(var.description, var.name)` (`modules/system_account/main.tf:12`), so when YAML omits `description` and the root passes `null` the module substitutes `var.name`; the resource never receives a null `description`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource. The 3.15 schema continues to mark `description` and `name` as Required (this was the contract on 3.1.0 as well). No bump-induced action required for either tree.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/system_account.md#Schema]. Repo declarations at [Source: terraform/konnect-teams/modules/system-account/main.tf:15-21] and [Source: .github/actions/provision-konnect-resources/terraform/modules/system_account/main.tf:10-14] (`coalesce` fallback at line 12).

### `konnect_system_account_access_token`

- **Classification:** `no-change`.
- **Attributes used:** `account_id`, `name`, `expires_at`.
- **3.1.0 → 3.15.0:** **3.2.1** fixed false diff on `terraform plan` for this resource (behavior-only). No HCL change; relevant to Story 1.6's clean-plan gate.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/system_account_access_token.md#Schema] (`account_id`, `expires_at`, `name` Required). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.2.1] ("Fixed false diff on the output of `terraform plan` for `konnect_system_account_access_token` resource"). Repo declarations at [Source: terraform/konnect-teams/modules/system-account/main.tf:119-124] and [Source: .github/actions/provision-konnect-resources/terraform/modules/system_account_access_token/main.tf:15].

### `konnect_system_account_role`

- **Classification:** `no-change`.
- **Attributes used:** `account_id`, `entity_id`, `entity_region`, `entity_type_name`, `role_name`. The outer tree hard-codes `entity_type_name` ∈ {"Control Planes", "API Products", "APIs"} and `role_name` ∈ {"Creator", "Viewer", "Admin", "Publisher"}, all of which remain in the enum lists for 3.15.
- **3.1.0 → 3.15.0:**
  - 3.10.0: New role values `Registration Approver`, `Content Editor` (additive).
  - 3.12.0: New role value `Debug Session Creator` (additive).
  - 3.13.0: Import support for the resource (operational improvement, not a schema break).
  - 3.15.0: New role values `Add On Admin`, `Add On Viewer` and new entity-type `Add Ons` (additive).
  - All role-enum changes are *additions* — every role the repo writes today (`Creator`, `Viewer`, `Admin`, `Publisher`) is still valid; the provider validates `role_name` against an enumerated list, so future operators who want the new roles can wire them through YAML without code changes.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/system_account_role.md#Schema] (full 3.15 enum). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.10.0]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.12.0]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.13.0]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.15.0]. Repo declarations at [Source: terraform/konnect-teams/modules/system-account/main.tf:31-116] (eight `count`-guarded blocks) and [Source: .github/actions/provision-konnect-resources/terraform/modules/system_account_role/main.tf:10].

### `konnect_system_account_team`

- **Classification:** `no-change`.
- **Attributes used:** `account_id`, `team_id`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/system_account_team.md#Schema]. Repo declarations at [Source: terraform/konnect-teams/modules/system-account/main.tf:24-28] and [Source: .github/actions/provision-konnect-resources/terraform/modules/system_account_team/main.tf:10].

### `konnect_team`

- **Classification:** `no-change`.
- **Attributes used:** `name`, `description`, `labels`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries change this resource's contract. 3.6.0 introduced the `team` and `team_list` data sources (additive; the repo doesn't use them).
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/team.md#Schema] (only `name` Required). [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.6.0]. Repo declarations at [Source: terraform/konnect-teams/main.tf:24-32] and [Source: .github/actions/provision-konnect-resources/terraform/modules/team/main.tf:10].

### `konnect_team_role`

- **Classification:** `no-change`.
- **Attributes used:** `team_id`, `entity_type_name`, `role_name`, `entity_id`, `entity_region`.
- **3.1.0 → 3.15.0:** Identical role-enum additions to `konnect_system_account_role` — see that section. 3.10.0, 3.12.0, 3.15.0 all add roles; 3.13.0 adds import support.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/team_role.md#Schema]. [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.10.0], [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.12.0], [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.13.0], [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md#3.15.0]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/team_role/main.tf:10].

### `konnect_team_user`

- **Classification:** `no-change`.
- **Attributes used:** `team_id`, `user_id`.
- **3.1.0 → 3.15.0:** No CHANGELOG entries name this resource.
- **Citations:** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/team_user.md#Schema]. Repo declaration at [Source: .github/actions/provision-konnect-resources/terraform/modules/team_user/main.tf:10].

## State migration operations

**No `terraform state mv`, `state rm`, or `import` operations are required** to land `kong/konnect = 3.15.0` over existing 3.1.0 state in either tree.

Reasoning:

- **3.1.0 → 3.15.0 is purely additive for every resource type the repository declares.** No resource was renamed, no resource type was removed, no `for_each` keying form changed in a way that would shift state addresses. New attributes (e.g., `sipr_enabled` on `konnect_portal`, the additional cloud-gateway transit-gateway sub-blocks, the new role-name enum values) are all Optional — existing state matches the 3.15 schema by definition because the repo doesn't write them.
- **The historical `konnect_portal` v2 → v3 migration via `konnect_portal_classic` was a 3.0.0 BREAKING change.** The repository pins `kong/konnect = 3.1.0` and uses the v3 `konnect_portal` resource directly. There is no `resource "konnect_portal_classic"` HCL declaration anywhere in the codebase (verified via `grep -rn 'konnect_portal_classic' --include='*.tf' .` — zero hits). The string does appear in the bundled `provision-konnect-resources/terraform/schema.json` (a generated provider-schema cache), but that is metadata, not a state-bearing declaration. The 3.0.0 transition has already been crossed; no `terraform state mv konnect_portal_classic.X konnect_portal.X` operation is needed.
- **The `count`-guarded `konnect_system_account_role` blocks in `terraform/konnect-teams/modules/system-account/main.tf` (lines 31, 42, 53, 64, 75, 86, 97, 108) preserve their existing addresses** (e.g., `module.system-account["flight-operations"].konnect_system_account_role.cp_creators[0]`). The `count = contains(...) ? 1 : 0` predicate evaluates the same way on 3.15 as on 3.1.0 because the entitlement strings (`konnect.control_plane`, `konnect.api`, etc.) are operator-supplied and not provider-affected.

**Implication for Story 1.4.** The `001-konnect-3-15-rename.sh` scripts in both trees are still required to land the standard architecture-doc P6 header / marker / idempotency convention, but their bodies are no-op guards. Suggested form (illustrative — Story 1.4 owns the actual implementation; the marker path below matches P6: `.terraform/migrations-applied`):

```bash
#!/usr/bin/env bash
set -euo pipefail

MIGRATIONS_DIR=".terraform/migrations-applied"
MARKER="${MIGRATIONS_DIR}/001-konnect-3-15-rename.applied"
if [[ -f "${MARKER}" ]]; then
  echo "001-konnect-3-15-rename: already applied — skipping."
  exit 0
fi

echo "001-konnect-3-15-rename: 3.1.0 → 3.15.0 is additive for all resource types in use; no terraform state mv operations required."
echo "  See _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md § State migration operations."

mkdir -p "${MIGRATIONS_DIR}"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKER}"
```

If a future audit (e.g., before a 3.15 → 3.x bump) discovers a real `state mv`, the script body can be extended below the marker check without altering callers.

**Operations table:** intentionally empty (no rows). The 3.1.0 → 3.15.0 hop requires zero state mutations — see the narrative above and AC3 in the story spec.

## Sources

- **CHANGELOG (primary diff source):**
  - [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/CHANGELOG.md] versions consulted — `## 3.0.0` (line 197), `## 3.1.0` (line 187), `## 3.2.0` (line 174), `## 3.2.1` (line 167), `## 3.3.0` (line 161), `## 3.4.0` (line 142), `## 3.4.1` (line 136), `## 3.4.2` (line 130), `## 3.4.3` (line 121), `## 3.5.0` (line 114), `## 3.6.0` (line 100), `## 3.7.0` (line 76), `## 3.8.0` (line 63), `## 3.9.0` (line 57), `## 3.10.0` (line 47), `## 3.11.0` (line 40), `## 3.12.0` (line 32), `## 3.13.0` (line 23), `## 3.14.0` (line 11), `## 3.15.0` (line 3).
- **Schema docs (current 3.15 contract per resource):** all under [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/docs/resources/]:
  - `api.md`, `api_document.md`, `api_implementation.md`, `api_publication.md`, `api_specification.md`, `api_version.md`, `application_auth_strategy.md`, `audit_log.md`, `audit_log_destination.md`, `centralized_consumer.md`, `centralized_consumer_key.md`, `cloud_gateway_configuration.md`, `cloud_gateway_custom_domain.md`, `cloud_gateway_network.md`, `cloud_gateway_private_dns.md`, `cloud_gateway_transit_gateway.md`, `gateway_control_plane.md`, `gateway_data_plane_client_certificate.md`, `integration_instance.md`, `integration_instance_auth_config.md`, `integration_instance_auth_credential.md`, `portal.md`, `portal_appearance.md`, `portal_auth.md`, `portal_custom_domain.md`, `portal_customization.md`, `portal_favicon.md`, `portal_logo.md`, `portal_page.md`, `portal_product_version.md`, `portal_snippet.md`, `portal_team.md`, `realm.md`, `system_account.md`, `system_account_access_token.md`, `system_account_role.md`, `system_account_team.md`, `team.md`, `team_role.md`, `team_user.md`.
- **Provider source (consulted as fallback only — CHANGELOG + docs were sufficient for every diff above):** [Source: /Users/jordi.fernandez/github/terraform-provider-konnect/internal/] (not invoked; no resource required Go-source spelunking).
- **Repo provider pins (current state):**
  - [Source: terraform/konnect-teams/main.tf:1-7] — outer tree pins `kong/konnect = 3.1.0` exact (declared inline in `terraform { required_providers { ... } }`; no separate `providers.tf`).
  - [Source: .github/actions/provision-konnect-resources/terraform/main.tf:1-16] — inner tree pins `kong/konnect = 3.1.0` exact, plus `Kong/konnect-beta = 0.11.1` (out of bump scope) and `devops-rob/terracurl = 1.0.1` (out of bump scope).
- **Inventory grep used to enumerate resources for AC1:**
  ```text
  grep -rEn 'resource[[:space:]]+"konnect[^"]*"|data[[:space:]]+"konnect[^"]*"' \
    terraform/ .github/actions/provision-konnect-resources/terraform/
  ```
- **Project-context constraints honored:**
  - [Source: _bmad-output/project-context.md#Terraform / HCL] — exact-pin discipline for `kong/konnect`; no `~>` ranges.
  - [Source: _bmad-output/project-context.md#Konnect provider (Terraform)] — schemas change between minor versions; verify `plan` before merging.
- **Planning-artifact references:**
  - [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1] — story BDD acceptance criteria.
  - [Source: _bmad-output/planning-artifacts/architecture.md#D3 — Konnect Provider Migration (3.1.0 → 3.15)] — migration decision and verification gate.
  - [Source: _bmad-output/planning-artifacts/architecture.md#P6 — Terraform state-migration script convention] — convention Story 1.4 will follow.
