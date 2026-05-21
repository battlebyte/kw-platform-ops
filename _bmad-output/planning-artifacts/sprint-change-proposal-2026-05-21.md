# Sprint Change Proposal - Unified Konnect Provisioning Engine

**Date:** 2026-05-21  
**Prepared by:** Developer Agent (Correct Course workflow)  
**Project:** kw-platform-ops  
**Scope classification:** Major  
**Status:** Revised after interrupted workflow

---

## Section 1: Issue Summary

The previous sprint plan no longer matches the project priority. Original Epics 3, 4, and 5 are cancelled. The new priority is to consolidate Konnect provisioning into one Sanofi-style workflow and source-of-truth tree.

Current fragmentation:

| Current workflow | Current source | Current state shape |
| --- | --- | --- |
| `onboard-konnect-teams.yaml` | `teams/*.yaml`, `terraform/konnect-teams/` | shared team state plus team-bucket behavior |
| `provision-auth-identity.yaml` | `konnect/auth-identity/resources.yaml` | org-ish bucket/key separate from team flow |
| `provision-konnect-team-resources.yaml` | `konnect/teams/<team>/resources.yaml`, `.github/actions/provision-konnect-resources/terraform/` | per-team buckets such as `kw.konnect.team.resources.<team>` |

Target picture:

- One workflow: `.github/workflows/provision-konnect-resources.yaml`
- One Terraform root: `terraform/konnect/`
- One source tree: `konnect/orgs/<org>/*.yaml`
- One S3/MinIO state bucket, with org-level key `konnect/orgs/<org>/terraform.tfstate`
- Per-team HashiCorp Vault token entries preserved
- YAML syntax mirrors `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/konnect/orgs/sanofi/`

The important correction from the interrupted proposal: this is not limited to org-level resources only. The unified engine should provision every Konnect resource type supported by this repository from the same org tree and plan/apply path. Adding future resource kinds should extend the module/schema, not create another workflow or state bucket.

---

## Section 2: Impact Analysis

### Epic Impact

| Epic | Status | Impact |
| --- | --- | --- |
| Epic 1 - Konnect Provider Modernization | Done / retained | Still foundational. Provider 3.15 work supports the unified module. |
| Epic 2 - Local-First Bootstrap | Done / retained | Still reused. MinIO, `init-terraform`, Vault, and state-bucket setup support the new workflow. |
| Old Epic 3 - Pluggable Kubernetes Target | Cancelled | No longer sprint priority. |
| Old Epic 4 - API Publishing & Action Contract Stability | Cancelled | No longer sprint priority. Relevant Terraform modules can still be reused by the unified engine. |
| Old Epic 5 - Documentation Synthesis | Cancelled | No longer sprint priority. |
| New Epic 3 - Unified Konnect Provisioning Engine | New backlog | Replaces old Epics 3/4/5 as the next implementation focus. |

### Story Impact

New Epic 3 stories:

| Story | Title | Status |
| --- | --- | --- |
| 3.1 | Build unified Terraform module `terraform/konnect/` | backlog |
| 3.2 | Migrate YAML to Sanofi-style `konnect/orgs/<org>/` syntax | backlog |
| 3.3 | Create single `provision-konnect-resources.yaml` workflow | backlog |
| 3.4 | Verify end-to-end and retire obsolete provisioning paths | backlog |

### Artifact Conflicts

| Artifact | Conflict | Resolution |
| --- | --- | --- |
| `prd.md` | Old requirements still described cancelled K8s/API/docs epics and old active workflow names. | Defer cancelled FRs and add FR35-FR38 for unified provisioning. |
| `architecture.md` | ADR #002 was too narrow: org-level only and excluded per-control-plane API resources. | Broaden ADR #002 to all supported Konnect resource types from the Sanofi-style org tree. |
| `epics.md` | Old Epic 3/4/5 story bodies remained after the new Epic 3 summary. | Replace old bodies with new Epic 3 stories only. |
| `sprint-status.yaml` | Old Epic 5 was still active despite cancellation. | Remove active Epic 5 entries and align new Epic 3 story IDs. |

---

## Section 3: Recommended Approach

Recommended path: **Direct Adjustment**.

No rollback of completed Epic 1 or Epic 2 work is needed. The new module can be built additively under `terraform/konnect/`, and legacy workflows/directories can remain until Story 3.4 verifies parity.

Implementation sequence:

1. Build `terraform/konnect/` using Sanofi's `fileset()` + `yamldecode()` + `merge()` pattern.
2. Migrate YAML into `konnect/orgs/konnect/*.yaml`.
3. Create `.github/workflows/provision-konnect-resources.yaml`.
4. Run end-to-end verification against MinIO + Vault, then retire obsolete paths.

Risk level: **Medium**. The risky part is schema consolidation, not state backend design. The state model is simpler than before because it removes per-team buckets.

---

## Section 4: Detailed Change Proposals

### `epics.md`

Replace old Epic 3/4/5 bodies with a single new Epic 3:

- Story 3.1: Build unified Terraform module `terraform/konnect/`
- Story 3.2: Migrate YAML to Sanofi-style `konnect/orgs/<org>/` syntax
- Story 3.3: Create single `provision-konnect-resources.yaml` workflow
- Story 3.4: Verify end-to-end and retire obsolete provisioning paths

Key requirement: the new Epic 3 must state that the unified engine covers all supported Konnect resource types, including teams, system accounts, control planes, control-plane child resources, portals, APIs, application auth strategies, authentication settings, identity provider mappings, and dashboards.

### `prd.md`

Add/adjust unified provisioning requirements:

- **FR35:** Provision every Konnect resource type supported by this repository through one workflow.
- **FR36:** Declare all Konnect resources in Sanofi-style YAML under `konnect/orgs/<org>/`.
- **FR37:** Use one S3/MinIO bucket with org-level key `konnect/orgs/<org>/terraform.tfstate`.
- **FR38:** Preserve per-team HashiCorp Vault entries for system account tokens.

Update NFR10 so the active workflow support matrix excludes retired workflows.

### `architecture.md`

Update ADR #002:

- Replace "org-level only" wording with "every supported Konnect resource declaration".
- Remove the previous out-of-scope statement for per-control-plane API resources.
- State that `.github/actions/provision-konnect-resources/terraform/modules/` modules can be moved, reused, or wrapped by `terraform/konnect/`, but there should be one Terraform implementation behind provisioning.
- Preserve single bucket + org-level key state model.
- Preserve HashiCorp Vault integration from ADR #001.

### `sprint-status.yaml`

Cancel old scope and track new Epic 3:

```yaml
epic-3-pluggable-k8s: cancelled
epic-4-api-publishing: cancelled

epic-3: backlog
3-1-build-unified-terraform-module: backlog
3-2-migrate-yaml-to-sanofi-style-konnect-orgs-syntax: backlog
3-3-create-single-provision-konnect-resources-workflow: backlog
3-4-verify-e2e-and-retire-obsolete-provisioning-paths: backlog
```

---

## Section 5: Implementation Handoff

**Scope:** Major - fundamental restructuring of the Konnect provisioning layer.

**Route to:** Developer agent.

**Primary implementation references:**

- `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/terraform/main.tf`
- `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/.github/workflows/konnect-provision.yaml`
- `/Users/jordi.fernandez/Downloads/sanofi-konnect-platform-ops-main/konnect/orgs/sanofi/*.yaml`
- Existing modules under `.github/actions/provision-konnect-resources/terraform/modules/`
- Existing Vault modules under `terraform/konnect-teams/modules/`

**Success criteria:**

- `terraform/konnect/` runs `terraform fmt -check -recursive` and `terraform validate`.
- The workflow uses one bucket and key `konnect/orgs/<org>/terraform.tfstate`.
- No workflow creates `kw.konnect.team.resources.<team>` buckets.
- `konnect/orgs/konnect/*.yaml` is the single provisioning source of truth.
- Per-team system account tokens are written to HashiCorp Vault.
- A second plan after apply is clean or contains only documented provider-computed drift.
- Legacy workflows and fragmented source directories are retired after verification.

---

## Checklist Progress

- [x] 1.1 Triggering issue identified: cancelled old Epics 3/4/5 and new unified provisioning priority.
- [x] 1.2 Core problem defined: fragmented workflows, fragmented Terraform roots, inconsistent YAML syntax, and per-team state buckets.
- [x] 1.3 Evidence gathered: current repo artifacts plus Sanofi reference structure.
- [x] 2.1-2.5 Epic impact assessed.
- [x] 3.1-3.4 Artifact conflicts assessed.
- [x] 4.1 Direct adjustment selected.
- [N/A] 4.2 Rollback rejected; completed Epics 1/2 are retained.
- [x] 4.3 MVP reviewed; cancelled scope deferred.
- [x] 5.1-5.5 Sprint Change Proposal components completed.

