# Sprint Change Proposal - Team Name Based IdP Group Mappings

Date: 2026-05-26
Project: kw-platform-ops
Mode: Batch

## 1. Issue Summary

The current identity provider mapping format requires `team_id` (Konnect UUID) in `konnect/orgs/konnect/identity-provider.yaml`.

This creates sequencing friction because team UUIDs are only known after teams are created from `konnect/orgs/konnect/teams.yaml`.

Requested change: allow and prefer `team_name` in `team_group_mappings`, and resolve UUIDs in Terraform after team creation.

## 2. Impact Analysis

### Epic Impact

- Impact level: Minor
- Existing epic scope remains valid.
- No epic reordering or new epic required.

### Story Impact

- Documentation/schema examples updated to use team-name references.
- IaC validation strengthened to enforce valid mapping references.
- No rollback needed.

### Artifact Conflicts

- PRD: no conflict; aligns with local-first and operator usability goals.
- Architecture: no architecture change required; this is a contract ergonomics refinement.
- UX: N/A (no significant UI surface for this flow).

### Technical Impact

- YAML source-of-truth for IdP mappings now uses stable team names.
- Terraform already resolves `team_name -> module.teams[team_name].id`; now guarded by explicit preconditions.
- Backward compatibility retained for legacy `team_id` mappings.

## 3. Recommended Approach

Selected path: Direct Adjustment (Option 1)

Rationale:
- Low implementation effort
- Low technical risk
- Improves maintainability and operator experience
- No timeline impact and no MVP scope change

Estimate:
- Effort: Low
- Risk: Low
- Timeline impact: None

## 4. Detailed Change Proposals

### A) Source-of-truth YAML update

Artifact: `konnect/orgs/konnect/identity-provider.yaml`
Section: `team_group_mappings`

OLD:
```yaml
# team_id is the Konnect team UUID (retrieve via `terraform output` or the Konnect UI).
team_group_mappings:
  - group: platform-admins
    team_id: "8adeebcb-14a3-4b2c-8839-c0f3fa54904e"

  - group: flight-ops
    team_id: "9ab54e88-cf01-430b-a106-f6aab93ec20c"
```

NEW:
```yaml
# Prefer team_name so Terraform can resolve the UUID after team creation.
# team_id is still supported for explicit/legacy mappings.
team_group_mappings:
  - group: platform-admins
    team_name: ground-operations

  - group: flight-ops
    team_name: flight-operations
```

Rationale: remove manual UUID lookup dependency and bind mapping to canonical team names.

### B) Terraform validation hardening

Artifact: `terraform/konnect/main.tf`
Section: locals + `terraform_data.validate_org_config` preconditions

OLD:
- No explicit validation for `team_group_mappings` team reference presence
- No explicit validation that `team_name` exists in declared teams

NEW:
- Added local `identity_provider_team_group_mappings_missing_team_ref`
- Added local `identity_provider_team_group_mappings_unknown_team_names`
- Added precondition: each mapping must define either `team_name` or `team_id`
- Added precondition: all `team_name` values must exist in `teams.yaml`

Rationale: fail fast with actionable errors, reduce runtime confusion.

### C) Terraform mapping block cleanup

Artifact: `terraform/konnect/main.tf`
Section: `module "identity_provider_team_group_mappings"`

OLD:
- Temporary inline notes/comments in logic block

NEW:
- Same behavior retained; temporary inline notes removed for clarity

Rationale: keep production IaC clear and maintainable.

## 5. Implementation Handoff

Scope classification: Minor

Handoff recipient: Developer agent (direct implementation)

Responsibilities:
- Keep name-based mapping as preferred path
- Preserve backward compatibility for `team_id`
- Ensure validations produce clear operator-facing errors

Success criteria:
- `identity-provider.yaml` supports team-name-based group mappings
- Terraform resolves names to IDs after team creation
- Invalid/missing team references fail with clear validation messages
- Existing `team_id` mappings still function

## Checklist Status Summary

- 1.1 Trigger identified: [x] Done
- 1.2 Problem statement: [x] Done
- 1.3 Evidence collected: [x] Done
- 2.1-2.5 Epic impact assessed: [x] Done
- 3.1 PRD conflict check: [x] Done
- 3.2 Architecture conflict check: [x] Done
- 3.3 UX conflict check: [N/A] Skip
- 3.4 Other artifacts check: [x] Done
- 4.1 Direct Adjustment: [x] Viable
- 4.2 Rollback: [x] Not viable
- 4.3 MVP Review: [x] Not viable
- 4.4 Path selection: [x] Done
- 5.1-5.5 Proposal components: [x] Done
- 6.1-6.2 Final review/proposal accuracy: [x] Done
- 6.3 User approval: [!] Action-needed
- 6.4 sprint-status update: [N/A] Skip (no epic/story changes)
- 6.5 Handoff confirmation: [x] Done

## Approval and Handoff Log

- User approval: yes (2026-05-26)
- Final scope classification: Minor
- Routed to: Developer agent
- Handoff status: Completed
