# Deferred Work

## Deferred from: code review of 1-1-audit-konnect-provider-3-15-schema-diffs-against-current-resource-usage (2026-05-08)

- **(MED)** `modules/cloud_gateway_configuration/main.tf:1-7` and `modules/control_plane/main.tf:1-7` declare `kong/konnect` source without a `version` pin — they inherit from root. Pre-existing inheritance, not introduced by Story 1.1; flag for Story 1.2 / 1.3 to either pin explicitly or accept inheritance deliberately.
- **(MED)** `konnect_audit_log_destination` authorization is `lookup(..., null)` for a Required attribute (audit mentions it in passing as "matches 3.1.0 behavior"). Same wiring-passes-null-for-required pattern flagged for `system_account`. Consider a unified watchpoint section in a future audit pass. Pre-existing wiring, not a Story 1.1 deliverable concern.
- **(LOW)** `konnect_centralized_consumer` module conditionally emits `consumer_groups`/`tags` based on `length() > 0`; audit's flat attribute list hides this. Matters only if 3.4.2's null-handling change (sets to `null`) affects state. Pre-existing module behavior.
- **(LOW)** `konnect_api` `spec_content` is `Requires replacement if changed` per 3.15 schema; audit's `no-change` classification is correct on the schema-diff axis but doesn't flag the ForceNew implication for Story 1.6's clean-plan exercise. Pre-existing schema fact.
- **(LOW)** `konnect_system_account_role` outer-tree "Count: 8" conflates 8 blocks with 0–8 actual instances (each `count`-guarded by entitlement). Affects state-address claims if entitlements differ between teams. Cosmetic.
- **(LOW)** `konnect_portal_auth` per-resource section's "Recommended Story 1.6 / MIGRATION.md §2 treatment" subsection is forward-prescriptive — borderline against the spec's "does not touch MIGRATION.md" rule. Reframe as "Watchpoint for Story 1.6" to match the cloud_gateway_configuration section style.
