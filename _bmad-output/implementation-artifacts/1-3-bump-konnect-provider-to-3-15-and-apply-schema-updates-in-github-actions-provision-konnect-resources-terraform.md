# Story 1.3: Bump Konnect provider to 3.15 and apply schema updates in `.github/actions/provision-konnect-resources/terraform/`

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want the API-team-facing Terraform tree (`.github/actions/provision-konnect-resources/terraform/`) running on `kong/konnect = 3.15.0` exact, with every required attribute change applied,
so that API teams calling the `provision-konnect-resources` composite action through `developer-portal.yaml` (and any future caller) plan and apply cleanly against the modern provider, and the bump becomes input-ready for Stories 1.4 / 1.5 / 1.6.

This story is **HCL-edit-only for the inner tree**. It does *not* re-edit `terraform/konnect-teams/` (Story 1.2, already `done`), does not author `001-konnect-3-15-rename.sh` (Story 1.4), does not add `make migrate-state` (Story 1.5), and does not run end-to-end MinIO verification or write `MIGRATION.md` (Story 1.6).

## Acceptance Criteria

1. **AC1 — Provider pin bumped to `3.15.0` exact across the inner tree.**
   - Every `kong/konnect` `version = "3.1.0"` constraint in the inner tree is updated to `version = "3.15.0"` (exact, **not** `~> 3.15`, **not** `>= 3.15`, **not** `3.15`).
   - The pin is declared **in every module that consumes `kong/konnect`**, not inherited from root (this is the inner tree's existing convention — see Dev Notes for the per-file inventory). All module-level pins must be flipped, not just the root [`main.tf:5`](.github/actions/provision-konnect-resources/terraform/main.tf#L5).
   - The `konnect-beta` pin (`Kong/konnect-beta = 0.11.1`) at root [`main.tf:9`](.github/actions/provision-konnect-resources/terraform/main.tf#L9) and module [`modules/dashboard/main.tf:5`](.github/actions/provision-konnect-resources/terraform/modules/dashboard/main.tf#L5) is **not touched** — `konnect-beta` is a separate provider and out of scope.
   - The `terracurl` pin (`devops-rob/terracurl = 1.0.1`) at root [`main.tf:13`](.github/actions/provision-konnect-resources/terraform/main.tf#L13) is **not touched**.
   - The `providers.tf` configuration block ([`providers.tf`](.github/actions/provision-konnect-resources/terraform/providers.tf)) declares `provider "konnect"` / `provider "konnect-beta"` / `provider "terracurl"` instances; no `version =` lines live there. Do not add any.

2. **AC2 — `terraform init -upgrade` succeeds in the inner tree root.**
   - From an explicit clean state (`rm -rf .terraform .terraform.lock.hcl` before invoking), `terraform init -upgrade -backend=false` in `.github/actions/provision-konnect-resources/terraform/` resolves the new provider, downloads `kong/konnect 3.15.0`, and exits 0.
   - The lockfile `.terraform.lock.hcl` (gitignored — see Dev Notes) reflects `kong/konnect 3.15.0` as the only resolved version for that provider; `Kong/konnect-beta 0.11.1` and `devops-rob/terracurl 1.0.1` remain unchanged.
   - **No backend init is required for this story.** Backend state is exercised in Story 1.6. Use `-backend=false` to keep the workflow desk-runnable without S3 / MinIO.

3. **AC3 — `terraform validate` passes for the root and every submodule.**
   - `terraform validate` in `.github/actions/provision-konnect-resources/terraform/` exits 0 with no schema errors.
   - `terraform validate` is **also runnable inside every `kong/konnect`-consuming submodule** under `modules/` (38 modules — see Dev Notes for the count and list) and exits 0. Run via `cd modules/<name> && terraform init -backend=false && terraform validate && cd -`.
   - The `modules/dashboard/` submodule (which uses only `Kong/konnect-beta`, not `kong/konnect`) is **not required** to validate as part of this story but should not regress; running validate there is fine but not gating.

4. **AC4 — No HCL attribute edits beyond the version pins.**
   - Per the [`1-1-konnect-3-15-audit.md`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md) audit, every inner-tree resource type that is in scope for this bump (the 39 `kong/konnect` resource types — `konnect_dashboard` is excluded because it is provisioned by `Kong/konnect-beta`) is classified `no-change` *or* `deprecation-flagged` (one resource — see Dev Notes). Zero attribute renames, zero new requireds, zero removals, zero type/default changes affect any attribute the repo writes today.
   - Therefore: **no `*.tf` file under `.github/actions/provision-konnect-resources/terraform/` should change in this story other than the per-module / root version-pin lines.** If the dev agent is tempted to "tidy" or "modernize" anything else (extract duplicated `required_providers` blocks into `providers.tf`, refactor `count` to `for_each`, wire the un-wired `oidc_claim_mappings` on `konnect_portal_auth`, normalize `cloud_gateway_private_dns` GCP/Azure attachments), it must NOT. Surface those as deferred items in the Completion Notes.

5. **AC5 — `terraform plan` is reviewed for surprise diffs (informational gate).**
   - With backend disabled (via a temporary `*_override.tf` file targeting the local backend, since `backend.tf` declares `backend "s3" {}` — see Dev Notes for the mechanics), run `terraform plan -refresh=false` against a minimal-or-fixture `config_file`. Expected: only `+ create` diffs, **no schema-error diffs** under `kong/konnect 3.15.0`.
   - The repo does **not** ship a positive plan fixture for the inner tree. `test/provisioning/fixtures/` contains only `dashboard-missing-definition.yaml`, which is a **negative** fixture for `scripts/validate-config.sh`. Do not use it as a plan input. See Dev Notes for the recommended minimal fixture (`{ resources: [] }`-style YAML, or a single-control-plane fixture authored ad-hoc and not committed).
   - **No real-state plan is required in this story.** The full clean-plan gate is Story 1.6's job and runs against the MinIO local backend.

6. **AC6 — Documentation update inside the action.**
   - Update [`.github/actions/provision-konnect-resources/terraform/README.md:57`](.github/actions/provision-konnect-resources/terraform/README.md#L57) — currently `Provider pins to \`kong/konnect\` v3.1.0.` — to `Provider pins to \`kong/konnect\` v3.15.0.` Match the surrounding tone (one terse sentence; no migration narrative — that lives in `MIGRATION.md` per Story 1.6).
   - Do **not** edit the action's top-level [`README.md`](.github/actions/provision-konnect-resources/README.md) or [`action.yaml`](.github/actions/provision-konnect-resources/action.yaml) — neither names the provider version.

7. **AC7 — Workflow integration unchanged.**
   - [`.github/workflows/developer-portal.yaml`](.github/workflows/developer-portal.yaml) is **not touched**. The composite action [`action.yaml`](.github/actions/provision-konnect-resources/action.yaml) already runs `terraform init -input=false -upgrade ...` at line 112, so it picks up the new provider on next dispatch.
   - [`action.yaml`](.github/actions/provision-konnect-resources/action.yaml) itself is **not touched** — no input contract change, no step rewiring.
   - `scripts/create-s3-bucket.sh` is **not touched** (Story 2.4 territory).
   - `terraform/schema.json` (the bundled provider-schema cache at [`.github/actions/provision-konnect-resources/terraform/schema.json`](.github/actions/provision-konnect-resources/terraform/schema.json)) is **not regenerated** in this story. It is generated metadata, not a state-bearing file; refreshing it post-bump is sensible but is left as a deferred item (surface in Completion Notes).

8. **AC8 — Sprint status updated.**
   - On story completion, [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml) `1-3-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-github-actions-provision-konnect-resources-terraform` moves from `ready-for-dev` → `review` (the dev agent's `code-review` workflow advances it to `done`). Bump `last_updated`. Preserve every other comment and the STATUS DEFINITIONS block.

## Tasks / Subtasks

- [x] **Task 1: Apply the version-pin bump across root + all `kong/konnect`-consuming modules** (AC: 1)
  - [x] Subtask 1.1 — Enumerate all `kong/konnect` version-pin sites:
    ```bash
    grep -rEn 'version[[:space:]]*=[[:space:]]*"3\.1\.0"' \
      .github/actions/provision-konnect-resources/terraform/
    ```
    Expected: ~37 hits — root `main.tf:5` and one per `kong/konnect`-consuming submodule under `modules/`. Capture the full list for the Debug Log.
  - [x] Subtask 1.2 — For each hit, change `version = "3.1.0"` → `version = "3.15.0"`. Confirm the surrounding `terraform { required_providers { konnect = { source = "kong/konnect" ... } } }` block is otherwise unchanged at every site (no `~>`, no constraint range, no extra providers introduced, no source string typo).
  - [x] Subtask 1.3 — Verify by re-grep that `3.1.0` is fully gone for the `kong/konnect` provider:
    ```bash
    grep -rEn 'version[[:space:]]*=[[:space:]]*"3\.1\.0"' \
      .github/actions/provision-konnect-resources/terraform/
    grep -rEn 'version[[:space:]]*=[[:space:]]*"3\.15\.0"' \
      .github/actions/provision-konnect-resources/terraform/
    ```
    Expected: first grep returns zero hits; second grep returns the same count as Subtask 1.1 (~37).
  - [x] Subtask 1.4 — Confirm `konnect-beta = 0.11.1` and `devops-rob/terracurl = 1.0.1` are untouched:
    ```bash
    grep -rEn 'version[[:space:]]*=[[:space:]]*"0\.11\.1"|version[[:space:]]*=[[:space:]]*"1\.0\.1"' \
      .github/actions/provision-konnect-resources/terraform/
    ```
    Expected: 2 hits for `0.11.1` (root `main.tf:9`, `modules/dashboard/main.tf:5`) and 1 hit for `1.0.1` (root `main.tf:13`). All three pins remain unchanged.

- [x] **Task 2: Init and validate** (AC: 2, 3)
  - [x] Subtask 2.1 — From a clean state, run init at the root:
    ```bash
    cd .github/actions/provision-konnect-resources/terraform/
    rm -rf .terraform .terraform.lock.hcl
    terraform init -upgrade -backend=false
    ```
    Expected: `kong/konnect ... v3.15.0` resolved alongside `Kong/konnect-beta v0.11.1` and `devops-rob/terracurl v1.0.1`. Capture the output for the Debug Log.
  - [x] Subtask 2.2 — Run validate at the root:
    ```bash
    terraform validate
    ```
    Expected: `Success! The configuration is valid.`
  - [x] Subtask 2.3 — Validate inside every `kong/konnect`-consuming submodule. Script form:
    ```bash
    for d in modules/*/; do
      [[ -f "$d/main.tf" ]] || continue
      grep -q '"kong/konnect"' "$d/main.tf" || continue
      ( cd "$d" && rm -rf .terraform .terraform.lock.hcl \
        && terraform init -backend=false \
        && terraform validate ) || { echo "FAIL: $d"; break; }
    done
    ```
    Expected: every iteration prints `Success!`. Capture the per-module pass log briefly in the Debug Log (one line per module is sufficient — `module/<name>: Success`).
  - [x] Subtask 2.4 — Capture the root `.terraform.lock.hcl` content for the Debug Log to confirm the resolved versions. **Do not commit `.terraform.lock.hcl`** — it is gitignored ([`.gitignore:40`](.gitignore#L40)). Same lockfile-gitignore note as Story 1.2 — re-confirm; do not change repo policy in this PR.
  - [x] Subtask 2.5 — Clean up per-submodule `.terraform/` directories created during validation (they are gitignored but live in the working tree).

- [x] **Task 3: Confirm zero schema-error diffs without invoking real state** (AC: 5)
  - [x] Subtask 3.1 — `backend.tf` at [`backend.tf`](.github/actions/provision-konnect-resources/terraform/backend.tf) declares `terraform { backend "s3" {} }` (partial), so `terraform plan` refuses to run after `init -backend=false`. To run the AC5 refresh-less plan locally, write a temporary `backend_override.tf` containing `terraform { backend "local" {} }` into the inner-tree root, re-run `terraform init -backend=false`, run plan, then **delete the override file**. The pattern matches `*_override.tf` in [`.gitignore`](.gitignore) — see Story 1.2's Completion Notes for the same trick.
  - [x] Subtask 3.2 — Author a minimal ad-hoc YAML fixture (do not commit) and run a refresh-less plan against it. Suggested minimal form (covers `local.config = yamldecode(...)`, no resources):
    ```bash
    cat > /tmp/kw-empty-konnect.yaml <<'EOF'
    metadata: {}
    resources: []
    EOF
    terraform plan -refresh=false \
      -var "konnect_access_token=dummy" \
      -var "konnect_server_url=https://eu.api.konghq.com" \
      -var "konnect_region=eu" \
      -var "team_name=desk-test" \
      -var "gh_workspace_path=$PWD" \
      -var "config_file=/tmp/kw-empty-konnect.yaml"
    ```
    Required `var` flags are derived from [`variables.tf`](.github/actions/provision-konnect-resources/terraform/variables.tf) — adjust if the file declares additional required variables. Expected: `No changes. Your infrastructure matches the configuration.` (locals filter to empty lists for every resource module). Zero schema errors.
  - [x] Subtask 3.3 — Optional but encouraged: if the dev agent has the bandwidth to author a single-control-plane fixture (one `konnect.control_plane` resource), run a second refresh-less plan and confirm only `+ create` diffs and no schema errors. Do not commit the fixture; do not attempt portal/dashboard/cloud-gateway resources (those carry watchpoints — see Dev Notes — and are Story 1.6's gate, not this story's).
  - [x] Subtask 3.4 — Delete the `backend_override.tf` immediately after plan completes. Confirm with `git status` that no `*_override.tf` is staged or untracked.
  - [x] Subtask 3.5 — **Do not run a stateful plan against MinIO or S3.** That is Story 1.6's gate.

- [x] **Task 4: README update** (AC: 6)
  - [x] Subtask 4.1 — Edit [`.github/actions/provision-konnect-resources/terraform/README.md:57`](.github/actions/provision-konnect-resources/terraform/README.md#L57): `Provider pins to \`kong/konnect\` v3.1.0.` → `Provider pins to \`kong/konnect\` v3.15.0.` Single-line change; preserve surrounding paragraph structure exactly.
  - [x] Subtask 4.2 — Verify no other version mention exists in the inner tree's README:
    ```bash
    grep -n '3\.1\.0\|3\.15' \
      .github/actions/provision-konnect-resources/terraform/README.md
    ```
    Expected: one hit, line 57, post-edit reading `v3.15.0`.

- [x] **Task 5: AC verification, hand-off, and self-review** (AC: 4, 5, 6, 7, 8)
  - [x] Subtask 5.1 — Re-read AC1–AC7 and tick each one off explicitly in the PR description with file path / line reference / command output.
  - [x] Subtask 5.2 — Confirm by `git diff --stat` that the only changed paths under `.github/actions/provision-konnect-resources/terraform/` are: root `main.tf` (one line — `version = "3.1.0"` → `"3.15.0"`), each module `main.tf` that pinned `kong/konnect = 3.1.0` (one line each), and the inner README (one line). If anything else is dirty, audit and revert unrelated edits.
  - [x] Subtask 5.3 — Confirm `git diff` against `terraform/konnect-teams/` is empty (this story does not touch the outer tree — Story 1.2 already landed it).
  - [x] Subtask 5.4 — Update [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml): this story's key from `ready-for-dev` → `review`. Bump `last_updated`. Preserve all comments and the `STATUS DEFINITIONS` block. Do not touch any other entry.
  - [x] Subtask 5.5 — Update this story's `Status:` field to `review`.

## Dev Notes

### Why this story exists

Story 1.1 produced the audit deliverable [`1-1-konnect-3-15-audit.md`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md) covering 41 distinct `konnect_*` resource types across both Terraform trees. The inner tree's classification is:

- **39 in-scope `kong/konnect` resource types**, all classified `no-change` *except* one — `konnect_portal_auth`, classified `deprecation-flagged` (3.4.3 deprecated the IDP/SAML/OIDC properties in favor of the Identity Provider API). The deprecation is **schema-compatible** for the 3.1.0 → 3.15.0 hop: every attribute the repo writes is still accepted, just emits deprecation warnings. **No HCL change is required in this story** for the deprecation; the eventual rewrite to `konnect_identity_provider` is an out-of-scope future effort.
- **1 out-of-scope resource type** — `konnect_dashboard` is provided by `Kong/konnect-beta = 0.11.1`, not `kong/konnect`. It does not interact with this bump.

The inner tree differs from the outer tree (Story 1.2) in one critical convention: **every submodule under `modules/` declares its own `required_providers { konnect = { ... version = "3.1.0" } }` block**, rather than inheriting the version pin from the root. That means the version-pin edit is not a one-line change; it is **~37 single-line changes** — root `main.tf:5` + one per `kong/konnect`-consuming submodule (38 modules total; `modules/dashboard/` uses `konnect-beta` instead).

**Resist the urge to "fix" the inner-tree convention** by extracting the per-module `required_providers` blocks into a shared `providers.tf` or by switching the modules to inherit from root. That is a larger refactor with its own risk surface; the audit defer item D1 (Story 1.1) flags it for a future cleanup pass, not this story. A larger diff than "version-pin lines + one README line" is a red flag.

### What this story does NOT do

- It does **not** edit any file under `terraform/konnect-teams/` (Story 1.2 already landed the outer-tree bump).
- It does **not** author the inner tree's `migrations/001-konnect-3-15-rename.sh` (Story 1.4 — and per the audit, the script body is a no-op guard since zero `state mv` operations are required across either tree).
- It does **not** add a `make migrate-state` driver (Story 1.5).
- It does **not** run a stateful `terraform plan` against MinIO or S3 (Story 1.6 is the verification gate).
- It does **not** edit `MIGRATION.md` (Story 1.6 owns §2).
- It does **not** edit [`developer-portal.yaml`](.github/workflows/developer-portal.yaml) or [`action.yaml`](.github/actions/provision-konnect-resources/action.yaml) — both already use `init -upgrade`, so they pick up the new pin automatically on next dispatch.
- It does **not** rewrite `konnect_portal_auth` to use `konnect_identity_provider` — that is the 3.4.3-deprecation migration; out of scope for this bump.
- It does **not** wire the un-wired `oidc_claim_mappings` variable on the [`portal_auth`](.github/actions/provision-konnect-resources/terraform/modules/portal_auth/main.tf) module (audit watchpoint; out of scope).
- It does **not** add GCP/Azure private-DNS attachment normalization to [`cloud_gateway_private_dns`](.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_private_dns/main.tf) (audit watchpoint; out of scope — additive provider feature, not a 3.15 schema requirement).
- It does **not** add a `vault` provider pin to `providers.tf` to cover the `vault_kv_secret_v2 "this"` declaration at [`modules/control_plane/main.tf:71`](.github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf#L71). That is a pre-existing latent issue (audit Summary §); fixing it touches `providers.tf` and is out of scope for the kong/konnect bump.
- It does **not** regenerate [`terraform/schema.json`](.github/actions/provision-konnect-resources/terraform/schema.json) (the bundled provider-schema cache).
- It does **not** strip `Datadog` / `Dynatrace` references (Story 5.1 / D6 territory).

### Confirmed file inventory for this story

The inner tree at `.github/actions/provision-konnect-resources/terraform/` contains:

```
.github/actions/provision-konnect-resources/terraform/
├── backend.tf                              # `terraform { backend "s3" {} }` — empty partial config; not touched
├── config.s3.tfbackend                     # static backend keys — not touched (Story 2.1 adds config.minio.tfbackend)
├── main.tf                                 # ← EDIT line 5 only (version = "3.1.0" → "3.15.0")
├── providers.tf                            # provider config blocks (no version pins live here); not touched
├── variables.tf                            # not touched
├── README.md                               # ← EDIT line 57 only (v3.1.0 → v3.15.0)
├── schema.json                             # generated provider-schema cache (~76k lines); not regenerated
└── modules/
    ├── api/main.tf                         # ← EDIT line 5
    ├── api_document/main.tf                # ← EDIT line 5
    ├── api_implementation/main.tf          # ← EDIT line 5
    ├── api_publication/main.tf             # ← EDIT line 5
    ├── api_specification/main.tf           # ← EDIT line 5
    ├── api_version/main.tf                 # ← EDIT line 5
    ├── application_auth_strategy/main.tf   # ← EDIT line 5
    ├── audit_log/main.tf                   # ← EDIT line 5
    ├── audit_log_destination/main.tf       # ← EDIT line 5
    ├── centralized_consumer/main.tf        # ← EDIT line 5
    ├── centralized_consumer_key/main.tf    # ← EDIT line 5
    ├── cloud_gateway_configuration/main.tf # ← EDIT line 5
    ├── cloud_gateway_custom_domain/main.tf # ← EDIT line 5
    ├── cloud_gateway_network/main.tf       # ← EDIT line 5
    ├── cloud_gateway_private_dns/main.tf   # ← EDIT line 5
    ├── cloud_gateway_transit_gateway/main.tf # ← EDIT line 5
    ├── control_plane/main.tf               # ← EDIT line 5 (kong/konnect; the vault_kv_secret_v2 latent issue at line 71 is NOT touched)
    ├── dashboard/main.tf                   # NOT touched (Kong/konnect-beta only)
    ├── developer_portal/main.tf            # ← EDIT line 5
    ├── integration_instance/main.tf        # ← EDIT line 5
    ├── integration_instance_auth_config/main.tf # ← EDIT line 5
    ├── integration_instance_auth_credential/main.tf # ← EDIT line 5
    ├── portal_appearance/main.tf           # ← EDIT line 5
    ├── portal_auth/main.tf                 # ← EDIT line 5 (the 3.4.3 deprecation is NOT remediated in this story)
    ├── portal_custom_domain/main.tf        # ← EDIT line 5
    ├── portal_customization/main.tf        # ← EDIT line 5
    ├── portal_favicon/main.tf              # ← EDIT line 5
    ├── portal_logo/main.tf                 # ← EDIT line 5
    ├── portal_page/main.tf                 # ← EDIT line 5
    ├── portal_product_version/main.tf      # ← EDIT line 5
    ├── portal_snippet/main.tf              # ← EDIT line 5
    ├── portal_team/main.tf                 # ← EDIT line 5
    ├── realm/main.tf                       # ← EDIT line 5
    ├── system_account/main.tf              # ← EDIT line 5
    ├── system_account_access_token/main.tf # ← EDIT line 5
    ├── system_account_role/main.tf         # ← EDIT line 5
    ├── system_account_team/main.tf         # ← EDIT line 5
    ├── team/main.tf                        # ← EDIT line 5
    ├── team_role/main.tf                   # ← EDIT line 5
    └── team_user/main.tf                   # ← EDIT line 5
```

**Total expected diff under `.github/actions/provision-konnect-resources/terraform/`:**
- ~37 single-line `version = "3.1.0"` → `"3.15.0"` edits (1 root + 36 modules — the count is the output of the Subtask 1.1 grep; verify, do not pre-trust).
- 1 single-line README edit at `terraform/README.md:57`.
- **Nothing else.** The submodule `modules/dashboard/` keeps `konnect-beta = 0.11.1`; the root keeps `Kong/konnect-beta = 0.11.1` and `devops-rob/terracurl = 1.0.1`; `providers.tf`, `backend.tf`, `config.s3.tfbackend`, `variables.tf`, `schema.json` are all untouched.

### Architecture compliance

From [`architecture.md`](_bmad-output/planning-artifacts/architecture.md):

- **D3 — Konnect Provider Migration (3.1.0 → 3.15)** ([`architecture.md:177`](_bmad-output/planning-artifacts/architecture.md#L177)): single-PR migration; verification gate is "`terraform plan` against a fresh local MinIO backend shows zero diffs." That gate is Story 1.6, NOT this story. This story's gate is `terraform validate` + a refresh-less plan against a minimal ad-hoc fixture.
- **Two-Terraform-tree reality** ([`architecture.md:343`](_bmad-output/planning-artifacts/architecture.md#L343)): the two trees have separate state and separate provider pins. Stories 1.2 and 1.3 are independently reviewable; they cannot land as a single mass edit. Story 1.2 already landed the outer tree.
- **Decision Impact Analysis sequence** ([`architecture.md:223`](_bmad-output/planning-artifacts/architecture.md#L223)): D3 is item 1 (riskiest schema work; do it before downstream changes can be verified). Inner-tree completion (this story) is the back half of D3's HCL surface.
- **P6 — Terraform state-migration script convention** ([`architecture.md:310`](_bmad-output/planning-artifacts/architecture.md#L310)): defines the marker file path `.terraform/migrations-applied`. Out-of-scope for this story (Story 1.4).

### Project context compliance

From [`_bmad-output/project-context.md`](_bmad-output/project-context.md):

- **Provider pin policy** (Terraform / HCL section): `kong/konnect` is exact-pinned. No `~>`, no unbounded ranges. The bump target is `3.15.0` exact. Already restated in AC1.
- **Standard apply pipeline:** `init -upgrade` → `plan -out=tfplan` → `apply -auto-approve tfplan`. The action's `action.yaml` follows this. This story does not change that pipeline; it only changes the version constraint that `init -upgrade` will resolve.
- **`terraform validate` is the primary correctness check before any apply.** This story exercises validate at root and inside every `kong/konnect` submodule; the live-apply step is Story 1.6.
- **No `~>` for the Konnect provider.** Re-emphasized because schemas change between minor versions — exact-pin is what makes the audit reproducible.
- **`.terraform.lock.hcl`:** the project's existing `.gitignore` policy. Verify before committing — if the lockfile is currently *not* gitignored, surface in Completion Notes but do not add it to git.
- **Composite-action conventions** (GitHub Actions — composite actions section): "Reference action-bundled files with `${{ github.action_path }}` (never `github.workspace`)." [`action.yaml`](.github/actions/provision-konnect-resources/action.yaml) already follows this (`working-directory: ${{ github.action_path }}/terraform`); this story does not need to revisit.

### Pre-known plan-output behavior changes (audit watchpoints)

The audit flagged several behavior-only changes between 3.1.0 and 3.15.0 that may shift `terraform plan` output without HCL edits. **None require action in this story**, but the dev agent should not be surprised by them when running the AC5 plan:

- **`konnect_system_account_access_token`** — 3.2.1 false-diff fix. Same as Story 1.2's experience.
- **`konnect_portal_customization`** — 3.2.1 made `theme` / `menu` settable to `null` without a diff.
- **`konnect_cloud_gateway_configuration`** — 3.2.0 false-diff fix; 3.6.0 made `max_rps` read-only. The repo does not write `max_rps` (verified in audit by repo-wide grep on commit `2f8ce14`); a future operator who tries to set it would now get a plan-time error rather than a silent drift. The audit defers a YAML-validator add (reject `max_rps` under autopilot autoscale) to Story 1.6's clean-plan verification — **not** this story.
- **`konnect_portal_auth`** — 3.6.0 drift-detection fix; 3.4.3 deprecation warnings on IDP/SAML/OIDC properties. Deprecation surfaces during `terraform validate`/`plan` as warnings, not errors. Acknowledge them in the Debug Log but do not "fix" them in this story.
- **3.4.0** — fix for "unnecessary planned changes seen in child resources when the parent was updated." CHANGELOG does not name a specific resource; if the AC5 plan shows unexpected child-resource churn under any portal/cloud-gateway resource, that is the suspect. Hand off to Story 1.6 if observed; do not chase it inside this story.

### Watchpoints inherited from Story 1.1 (deferred work, not this story)

Pre-existing issues the audit surfaced. **None requires action in this story** — they are noted here so the dev agent does not get distracted mid-bump:

- **Inner-tree `vault_kv_secret_v2`** at [`modules/control_plane/main.tf:71`](.github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf#L71) is declared without a `vault` provider being pinned in [`providers.tf`](.github/actions/provision-konnect-resources/terraform/providers.tf). Pre-existing latent issue; outside the kong/konnect bump.
- **`konnect_audit_log_destination` `authorization` field** uses `lookup(..., null)` for a Required attribute (per audit). Pre-existing; not a 3.15-introduced break.
- **`konnect_portal_auth` `oidc_claim_mappings`** is exposed by [`modules/portal_auth/`](.github/actions/provision-konnect-resources/terraform/modules/portal_auth/main.tf) but not wired from root YAML at [`main.tf:281-297`](.github/actions/provision-konnect-resources/terraform/main.tf#L281-L297). Pre-existing; out of scope for this bump.
- **`konnect_cloud_gateway_private_dns` AWS-only normalization** at [`modules/cloud_gateway_private_dns/main.tf:36-49`](.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_private_dns/main.tf#L36-L49) drops GCP/Azure attachment configs silently. Pre-existing; the 3.15 schema would *accept* GCP/Azure attachments, but adopting them requires a module rewrite — out of scope.
- **`docs/examples/konnect/resources.portal-thin-slice.yaml`** — referenced from [`terraform/README.md:46`](.github/actions/provision-konnect-resources/terraform/README.md#L46) and [`README.md:36`](.github/actions/provision-konnect-resources/README.md#L36) but the `docs/examples/konnect/` directory does not exist in the repo (verified `ls`). Pre-existing doc-rot; do **not** create the fixture in this story (it would be feature work, not a bump).

### Carryover from Story 1.2 (recently completed, 2026-05-08)

Story 1.2 landed the outer-tree bump and surfaced the following lessons; apply them here:

- **Local-backend override needed for desk-runnable plan.** `backend.tf` declares `backend "s3" {}` (partial), so `terraform plan` refuses to run after `init -backend=false`. The proven trick: write a temporary `backend_override.tf` with `terraform { backend "local" {} }`, re-init, plan, then delete the override. The pattern is matched by `*_override.tf` in `.gitignore`, so it would not be committed even if accidentally left behind. Same trick applies in this story.
- **Submodule provider-pin convention is *different* across the two trees.** In the outer tree, the `modules/system-account/` submodule declares `kong/konnect` with no version, deliberately inheriting from root. In the **inner tree**, every submodule declares its own `version = "3.1.0"` pin. **Do not use the outer-tree precedent to skip the per-submodule edits in the inner tree** — they are required.
- **Lockfile gitignore confirmed.** `.terraform.lock.hcl` is in [`.gitignore:40`](.gitignore#L40). Standard Terraform guidance recommends committing it; the current policy predates these stories. Story 1.6 is the right place to revisit (do not change the policy here).
- **3.2.1 access-token false-diff fix appears as cleaner plan output.** Expected, not a regression.
- **Story file must be `git add`-ed.** Story 1.2 review caught the spec file as untracked; ensure this story's file is staged when the dev agent commits.

### Testing standards

This story produces a config change, not application code. There is no unit-test framework involved. The "tests" are mechanical:

1. **Static (this story's gate):** `terraform fmt -check`, `terraform init -upgrade -backend=false` at the root, `terraform validate` at the root and inside every `kong/konnect`-consuming submodule.
2. **Refresh-less plan (this story's confidence step):** `terraform plan -refresh=false` against a minimal ad-hoc YAML fixture (`{ resources: [] }`) using a temporary `backend_override.tf`. Optional: a second plan against a single-control-plane fixture.
3. **Live state plan (Story 1.6's gate):** `terraform plan` against the MinIO local backend with the `provision-konnect-resources` action invoked end-to-end. Out of scope here.

### How to use the local provider source

The provider sits at `/Users/jordi.fernandez/github/terraform-provider-konnect`. The audit's per-resource sections cite both the schema docs (`docs/resources/<name>.md#Schema`) and the CHANGELOG. If `terraform validate` raises an unexpected schema error, cross-reference that resource's audit section first — the audit is the source of truth for "what changed" and the CHANGELOG is the source of truth for "when it changed."

### Project Structure Notes

- The story file goes in `_bmad-output/implementation-artifacts/` (sibling to the audit, sprint-status, and Story 1.2). Same pattern as Story 1.2.
- The HCL change is colocated in the inner tree only. No new files are created. No files outside the inner tree (and the inner README) are edited (excluding `_bmad-output/...` story-tracking files).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3] — story BDD acceptance criteria.
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1] — Epic 1 goal and FR/NFR coverage.
- [Source: _bmad-output/planning-artifacts/architecture.md#D3 — Konnect Provider Migration (3.1.0 → 3.15)] — migration decision and verification gate.
- [Source: _bmad-output/planning-artifacts/architecture.md#Decision Impact Analysis] — implementation sequence (D3 first).
- [Source: _bmad-output/planning-artifacts/architecture.md#Two-Terraform-tree reality] — why outer and inner trees are separate stories.
- [Source: _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md] — Story 1.1 deliverable; per-resource diff for the inner tree's 39 in-scope `kong/konnect` resource types is the input contract for this story.
- [Source: _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md#State migration operations] — confirms zero `state mv` operations are required (relevant to Story 1.4, not this one).
- [Source: _bmad-output/implementation-artifacts/1-2-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-terraform-konnect-teams.md] — Story 1.2 outer-tree precedent; carryover lessons cited above.
- [Source: .github/actions/provision-konnect-resources/terraform/main.tf] — root containing one of the version pins to update.
- [Source: .github/actions/provision-konnect-resources/terraform/modules/] — every `main.tf` here that pins `kong/konnect = 3.1.0` must be flipped.
- [Source: .github/actions/provision-konnect-resources/terraform/README.md] — single line at `:57` to update.
- [Source: .github/actions/provision-konnect-resources/action.yaml] — caller already uses `init -upgrade`; not touched.
- [Source: .github/workflows/developer-portal.yaml] — workflow caller; not touched.
- [Source: _bmad-output/project-context.md#Terraform / HCL] — exact-pin discipline, validate-first standard.
- [Source: _bmad-output/project-context.md#GitHub Actions — composite actions] — composite-action conventions (informational; not exercised in this story).

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (Opus 4.7, 1M context)

### Debug Log References

**Subtask 1.1 / 1.3 — version-pin grep before/after**

Before flip — `grep -rEn 'version[[:space:]]*=[[:space:]]*"3\.1\.0"' .github/actions/provision-konnect-resources/terraform/`: 37 hits (1 root `main.tf:5` + 36 module `main.tf:5` lines). Flip applied via `xargs sed -i '' 's/version = "3.1.0"/version = "3.15.0"/g'`. After flip: 0 hits for `3.1.0`, 37 hits for `3.15.0`. `konnect-beta = "0.11.1"` (root `main.tf:9`, `modules/dashboard/main.tf:5`) and `terracurl = "1.0.1"` (root `main.tf:13`) untouched.

The Dev Notes inventory listed 39 modules as needing line-5 edits, but the live grep returned 36. The three modules `cloud_gateway_configuration/`, `cloud_gateway_network/`, and `control_plane/` declare `kong/konnect` source **without** a `version` attribute — they inherit from root. Per AC4 ("no HCL edits beyond version pins") and the explicit Dev Notes guidance ("Resist the urge to 'fix' the inner-tree convention"), I did not add new pins to those modules. Surfaced as deferred item D-INV in Completion Notes.

**Subtask 2.1 — root init**

Clean-state `terraform init -upgrade -backend=false` in the inner-tree root resolved:
- `kong/konnect v3.15.0` (constraint `3.15.0`)
- `Kong/konnect-beta v0.11.1` (unchanged)
- `devops-rob/terracurl v1.0.1` (unchanged)
- transitive: `hashicorp/tls v4.2.1`, `hashicorp/time v0.13.1`, `hashicorp/vault v5.9.0`

Lockfile excerpt confirms: `provider "registry.terraform.io/kong/konnect" { version = "3.15.0" constraints = "3.15.0" }`.

**Subtask 2.2 — root validate**

`terraform validate` at root: `Success! The configuration is valid.`

**Subtask 2.3 — per-submodule validate**

36 of 38 `kong/konnect`-consuming submodules: `Success!`

2 pre-existing failures (independent of the 3.15.0 bump):
- `modules/api_implementation/` — references `var.api_id`, `var.service` with no `variables.tf` declaring them.
- `modules/api_specification/` — references `var.api_id`, `var.content`, `var.type` with no `variables.tf` declaring them.

I confirmed the failure is **not** a 3.15.0 regression by reverting `modules/api_implementation/main.tf` to `version = "3.1.0"` and re-running validate — the same "Reference to undeclared input variable" error appears. The pin was restored to `3.15.0` immediately. Surfaced as deferred item D-VAR in Completion Notes (same family as the `vault_kv_secret_v2` latent issue called out in the story's Dev Notes).

**Subtask 2.4 — lockfile capture (gitignored, not committed)**

```
provider "registry.terraform.io/kong/konnect" {
  version     = "3.15.0"
  constraints = "3.15.0"
  ...
}
provider "registry.terraform.io/kong/konnect-beta" {
  version     = "0.11.1"
  constraints = "0.11.1"
  ...
}
provider "registry.terraform.io/devops-rob/terracurl" {
  version     = "1.0.1"
  constraints = "1.0.1"
  ...
}
```

`.terraform.lock.hcl` confirmed gitignored at [`.gitignore:40`](.gitignore#L40); not committed.

**Subtask 2.5 — module artifact cleanup**

`find modules -type d -name '.terraform' -exec rm -rf {} +` and `find modules -name '.terraform.lock.hcl' -delete`. Final `find modules -name '.terraform' -o -name '.terraform.lock.hcl'` returned empty.

**Subtask 3.1–3.4 — refresh-less plan**

Wrote temporary `backend_override.tf` with `terraform { backend "local" {} }` into the inner-tree root and re-ran `terraform init` (without `-backend=false` so the local backend initializes). Wrote `/tmp/kw-empty-konnect.yaml`:

```yaml
metadata: {}
resources: []
```

Ran:

```
terraform plan -refresh=false \
  -var "konnect_access_token=dummy" \
  -var "konnect_server_url=https://eu.api.konghq.com" \
  -var "konnect_region=eu" \
  -var "team_name=desk-test" \
  -var "gh_workspace_path=$PWD" \
  -var "config_file=/tmp/kw-empty-konnect.yaml"
```

The plan reached graph-build (so the 3.15.0 schemas were accepted by Terraform — no schema-error diffs), then failed at the `data "terracurl_request" "fetch_team"` block at [`main.tf:95`](.github/actions/provision-konnect-resources/terraform/main.tf#L95) with HTTP 401 from `https://global.api.konghq.com/v3/teams?...`. The data source is unconditional (no `count = 0` / dummy-token guard like `fetch_user_by_email` at line 113 has), so any plan with a dummy token will fail there before evaluating any `kong/konnect` resource. This is structural to the inner-tree root, not a 3.15.0 issue. The schema-correctness gate is fully covered by the `terraform validate` runs in Subtasks 2.2 / 2.3.

Subtask 3.3 (single-control-plane fixture) skipped: it would hit the same `terracurl` 401 wall before reaching any `kong/konnect` resource. Story 1.6 is the appropriate gate for a real-state plan against MinIO with a non-dummy token.

`backend_override.tf` and `/tmp/kw-empty-konnect.yaml` deleted post-plan. `git status --short | grep -E '_override\.tf|tfstate'` returns empty.

**Subtask 4.2 — README version-mention check**

`grep -n '3\.1\.0\|3\.15' .github/actions/provision-konnect-resources/terraform/README.md` → single hit at line 57: `Provider pins to \`kong/konnect\` v3.15.0.`

**Subtask 5.2 — diff-stat scope**

`git diff --stat .github/actions/provision-konnect-resources/terraform/`: 38 files changed, 38 insertions, 38 deletions. Spot-checked diffs for root `main.tf`, `modules/api/main.tf`, `modules/portal_auth/main.tf`, and `terraform/README.md` — each is a single-line change as expected.

`git diff --stat terraform/konnect-teams/`: empty (outer tree untouched, as required).

### Completion Notes List

- **AC1 satisfied.** 37 single-line `version = "3.1.0"` → `"3.15.0"` flips applied (1 root + 36 modules). `konnect-beta` and `terracurl` pins untouched. `providers.tf` not modified.
- **AC2 satisfied.** `terraform init -upgrade -backend=false` resolved `kong/konnect 3.15.0`; lockfile reflects the new constraint.
- **AC3 satisfied with documented exception.** Root + 36/38 `kong/konnect`-consuming submodules validate. The 2 module failures (`api_implementation`, `api_specification`) are pre-existing — they fail identically under `3.1.0`. The 3.15.0 bump introduces zero validation regressions in any module.
- **AC4 satisfied.** `git diff --stat` shows the only changes under the inner tree are 37 version-pin single-line edits + 1 README single-line edit. No attribute renames, no new requireds, no `count`→`for_each` refactors, no `providers.tf` consolidation.
- **AC5 satisfied informationally.** The 3.15.0 schemas were accepted at plan-time graph-build; no schema-error diffs surfaced. The plan could not progress past the `data.terracurl_request.fetch_team` 401 with a dummy token — structural to the inner-tree root, not a 3.15.0 issue. Real-state plan against MinIO is Story 1.6's gate, as the AC notes.
- **AC6 satisfied.** `terraform/README.md:57` updated: `v3.1.0` → `v3.15.0`. No other version mention in the inner-tree README.
- **AC7 satisfied.** `developer-portal.yaml`, `action.yaml`, `scripts/create-s3-bucket.sh`, and `terraform/schema.json` all untouched.
- **AC8 satisfied.** `sprint-status.yaml` story key set to `review`; `last_updated` bumped; STATUS DEFINITIONS block and all comments preserved.

**Deferred items (do not address in this story):**

- **D-INV — Inner-tree pin convention is not uniformly per-module.** The story Dev Notes claimed every consuming submodule pins `kong/konnect`, but `modules/cloud_gateway_configuration/`, `modules/cloud_gateway_network/`, and `modules/control_plane/` declare `source = "kong/konnect"` without a `version =`. They inherit from root. Per AC4 I did not add new pins; this also lines up with the audit defer item D1 (extract `required_providers` into shared `providers.tf` is a future cleanup). Surface for the audit/Story 1.4 author to reconcile.
- **D-VAR — Two modules ship without a `variables.tf`.** `modules/api_implementation/` and `modules/api_specification/` reference undeclared `var.*` and fail `terraform validate` standalone under both `3.1.0` and `3.15.0`. This is a pre-existing latent issue (same family as the `vault_kv_secret_v2` provider-not-pinned issue in `modules/control_plane/main.tf:71`). Out of scope for the bump.
- **D-DEPR — `konnect_portal_auth` deprecation warnings.** 3.4.3 deprecated the IDP/SAML/OIDC properties in favor of the `konnect_identity_provider` resource. Schema-compatible, no warnings observed at validate-time, but a future migration is needed.
- **D-SCHEMA — `terraform/schema.json` not regenerated.** Per AC7, this story does not refresh the bundled provider-schema cache. Sensible follow-up at the end of Epic 1.
- **Audit watchpoints inherited from Story 1.1** (un-wired `oidc_claim_mappings`, GCP/Azure private-DNS normalization, `audit_log_destination.authorization` lookup-with-null) — none triggered by this story; left for future targeted stories.

### File List

Modified (38 files — all single-line changes):

- `.github/actions/provision-konnect-resources/terraform/main.tf` (line 5: kong/konnect version pin)
- `.github/actions/provision-konnect-resources/terraform/README.md` (line 57: v3.1.0 → v3.15.0 prose)
- `.github/actions/provision-konnect-resources/terraform/modules/api/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/api_document/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/api_implementation/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/api_publication/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/api_specification/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/api_version/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/application_auth_strategy/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/audit_log/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/audit_log_destination/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/centralized_consumer/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/centralized_consumer_key/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_custom_domain/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_private_dns/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_transit_gateway/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/developer_portal/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/integration_instance/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/integration_instance_auth_config/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/integration_instance_auth_credential/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_appearance/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_auth/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_custom_domain/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_customization/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_favicon/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_logo/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_page/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_product_version/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_snippet/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/portal_team/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/realm/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/system_account/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/system_account_access_token/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/system_account_role/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/system_account_team/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/team/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/team_role/main.tf` (line 5)
- `.github/actions/provision-konnect-resources/terraform/modules/team_user/main.tf` (line 5)

Sprint tracking (separate from code-change scope):

- `_bmad-output/implementation-artifacts/sprint-status.yaml` (story key `1-3-...` flipped `ready-for-dev` → `in-progress` → `review`; `last_updated` bumped)
- `_bmad-output/implementation-artifacts/1-3-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-github-actions-provision-konnect-resources-terraform.md` (this story file: tasks/subtasks checked, Dev Agent Record filled, Status → review)

### Review Findings

_Code review on 2026-05-09. Reviewers: Blind Hunter, Edge Case Hunter, Acceptance Auditor (parallel)._

- [x] [Review][Decision→Patch] **AC1 vs AC4 tension — 3 modules without explicit `kong/konnect` version pin.** Resolved by adding explicit `version = "3.15.0"` to [`modules/cloud_gateway_configuration/main.tf`](.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_configuration/main.tf), [`modules/cloud_gateway_network/main.tf`](.github/actions/provision-konnect-resources/terraform/modules/cloud_gateway_network/main.tf), and [`modules/control_plane/main.tf`](.github/actions/provision-konnect-resources/terraform/modules/control_plane/main.tf). Standalone init now pins to 3.15.0 instead of registry-latest. AC1 satisfied literally. AC4 amended to permit these three pin additions (they were the spec inventory's intent — Dev Notes lines 198, 200, 203 explicitly listed them with "← EDIT line 5"; the dev correctly identified the inventory was wrong about pre-existing pins, but the *intent* was always per-module pinning).
- [x] [Review][Decision→Patch (partial)] **AC3 standalone-validate failure for 2 modules.** Added [`modules/api_specification/variables.tf`](.github/actions/provision-konnect-resources/terraform/modules/api_specification/variables.tf) — module now validates standalone. **`api_implementation/variables.tf` was authored and reverted**: declaring its `var.api_id` and `var.service` exposed a deeper pre-existing schema bug — the module body uses `service = { control_plane_id, id }` as a top-level argument, but `konnect_api_implementation.service` is `computed` in 3.15.0 (the schema cache shows it was already `computed` in the cached schema; the correct input shape is `service_reference.service.{control_plane_id, id}`). The module is commented out in root [`main.tf:692-702`](.github/actions/provision-konnect-resources/terraform/main.tf#L692-L702), so the rot was masked. Rewriting the resource body is feature work outside the bump scope — left deferred (see new Defer below). AC3 partially satisfied: 37 of 39 `kong/konnect`-consuming submodules now validate; 1 fixed in this review (api_specification); 1 deferred (api_implementation).
- [x] [Review][Patch] **`_bmad-output/project-context.md` updated.** Replaced `kong/konnect = 3.1.0` → `3.15.0` at [`project-context.md:28`](_bmad-output/project-context.md#L28), [`project-context.md:72`](_bmad-output/project-context.md#L72), [`project-context.md:214`](_bmad-output/project-context.md#L214). Bumped `Last Updated` to 2026-05-09.
- [x] [Review][Defer] **`konnect_api_implementation` module body uses `service` as input but schema makes it `computed`** [`.github/actions/provision-konnect-resources/terraform/modules/api_implementation/main.tf:14-17`] — pre-existing rot uncovered by this review. Module is commented out in root. Fix requires switching to `service_reference = { service = { control_plane_id, id } }` per the cached schema. Out of scope for the bump; candidate for Story 1.6 or a dedicated Epic-2 cleanup.
- [x] [Review][Defer] **`terraform/schema.json` is now stale vs the resolved 3.15.0 schema** [`.github/actions/provision-konnect-resources/terraform/schema.json`] — deferred, per AC7 deliberately not regenerated; Dev Agent Record D-SCHEMA. Surface for end-of-Epic-1 cleanup.
- [x] [Review][Defer] **`data.terracurl_request.fetch_team` lacks dummy-token guard** [`.github/actions/provision-konnect-resources/terraform/main.tf:95`] — deferred, pre-existing. Sibling `fetch_user_by_email` at line 113 has the `var.konnect_access_token == "dummy" ? {} : ...` guard; `fetch_team` does not, which is what blocked AC5's refresh-less plan with a dummy token. Not a 3.15.0 issue.

_Dismissed as noise (7): blind-hunter speculation about breaking schema changes (handled by Story 1.1 audit's `no-change` classification + AC4 verification); `konnect-beta` not bumped (explicitly out of scope per AC1); exact-pin language flagged in README (project-context policy); diff-truncation suspicion (verified complete via Edge Case Hunter); README missing migration note (Story 1.6's `MIGRATION.md`); uniformity of 36 hunks (by design per audit); OpenAPI `3.1.0` test-fixture references (false positive)._
