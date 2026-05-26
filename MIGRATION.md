# Migration Guide — kw-platform-ops

This document records the migration paths an operator must follow when upgrading a fork of `kw-platform-ops` across breaking-change boundaries. Each section follows the **Affected / Before / After / Remediation** format defined in [`_bmad-output/planning-artifacts/architecture.md` § P5](_bmad-output/planning-artifacts/architecture.md#L286-L308).

## Migration 1 — Legacy cloud-only → local-first

<!-- Authored by Story 5.2 (Epic 5 — Documentation Synthesis). Reserved structurally to preserve anchor stability for downstream documents. -->

_This section is reserved for Story 5.2 (Epic 5). Do not author §1 content in this story._

## Migration 2 — Konnect provider 3.1.0 → 3.15.0

The Konnect Terraform provider was upgraded from `kong/konnect = 3.1.0` to `kong/konnect = 3.15.0` across both Terraform trees in the repository. The per-resource schema audit ([`_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)) classified 39 of 40 in-scope resource types as **no-change**, 1 as **deprecation-flagged** (`konnect_portal_auth` OIDC/SAML properties deprecated in 3.4.3), and 0 as **attribute-edit-required** or **state-mv-required**. Operators with existing state at provider version 3.1.0 can upgrade in place by running a single `make migrate-state` invocation after re-initializing each Terraform tree against their state backend — no `terraform state mv` operations are required.

**Affected:**

- HCL provider pin (Stories 1.2 + 1.3):
  - [`terraform/konnect-teams/main.tf`](terraform/konnect-teams/main.tf) (lines 4-5, `required_providers.konnect.version`)
  - [`.github/actions/provision-konnect-resources/terraform/main.tf`](.github/actions/provision-konnect-resources/terraform/main.tf) (same lines, same key)
- State-migration scripts (Story 1.4):
  - [`terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh)
  - [`.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`](.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh)
- Migration driver (Story 1.5):
  - [`Makefile`](Makefile) — `migrate-state` target (lines 46-49) + `.PHONY` entry (line 56)
  - [`scripts/run-migrations.sh`](scripts/run-migrations.sh) — per-tree helper

**Before:**

```hcl
terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.1.0"
    }
  }
}
```

**After:**

```hcl
terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.15.0"
    }
  }
}
```

**Remediation:**

> The procedure below is the end-to-end operator path for a fork that has existing state at 3.1.0 and wants to land at 3.15.0 with zero resource destruction. Every command is copyable verbatim from a fresh fork-clone. The exact same sequence was executed end-to-end during Story 1.6's verification (see Debug Log in [`_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md`](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md)) and is therefore known-runnable on macOS + Linux with the docker-compose stack as the state backend.

1. **Pre-flight — confirm the fork is on the 3.15.0 pin.**
   ```bash
   grep 'version = "3.15.0"' \
     terraform/konnect-teams/main.tf \
     .github/actions/provision-konnect-resources/terraform/main.tf
   ```
   _Expected: two matches._ If either file still shows `version = "3.1.0"`, pull the Epic 1 changes from upstream and re-run before continuing.

2. **Bring up the local state backend (MinIO via docker-compose).**
   ```bash
   make prepare
   ```
   _Expected: `minio`, `vault`, and `minio-create-bucket` containers running; bucket `tfstate` reachable at `http://localhost:9000/tfstate` (HTTP 200 or 403 — anonymous access is denied by design)._ See [`docker-compose.yaml`](docker-compose.yaml). Fork-operators already running a non-MinIO backend (e.g., AWS S3) can skip this step and instead point Terraform at their existing backend in step 4.

   > **Verification gotcha — `make prepare`'s `vault-pki` step.** `make prepare` chains a Vault PKI bootstrap that targets `VAULT_ADDR=https://vault.kong-cx.com` by default and will fail against the local dev Vault on port 8300. The MinIO container and bucket creation happen *before* the PKI step, so the state backend is ready even if `vault-pki` errors out. For the `MIGRATION.md` §2 procedure (state backend only), the PKI failure can be ignored. To bring up only what this guide needs: `docker-compose up -d minio vault minio-create-bucket`.

3. **Export environment for the verification session.**
   ```bash
   # Konnect API access (read the token from your local act.secrets — the file uses key name KONNECT_PAT)
   export KONNECT_TOKEN="$(grep -E '^KONNECT_PAT=' act.secrets | cut -d= -f2-)"
   export TF_VAR_konnect_token="$KONNECT_TOKEN"            # outer tree (terraform/konnect-teams)
   export TF_VAR_konnect_access_token="$KONNECT_TOKEN"     # inner tree (provision-konnect-resources)
   export KONNECT_SERVER_URL="${KONNECT_SERVER_URL:-https://eu.api.konghq.com}"
   export TF_VAR_konnect_server_url="$KONNECT_SERVER_URL"

   # AWS-compat env routes the S3 backend at the local MinIO. Skip if using real AWS S3.
   export AWS_ENDPOINT_URL=http://localhost:9000
   export AWS_ACCESS_KEY_ID=minio-root-user
   export AWS_SECRET_ACCESS_KEY=minio-root-password
   export AWS_REGION=main

   # Preflight: a silently-empty KONNECT_TOKEN causes the inner tree's
   # plan in step 6 to crash on the unguarded fetch_team data source
   # with "Invalid index — data[0]" (see _bmad-output/implementation-artifacts/deferred-work.md
   # § "Deferred from: Story 1.6 verification" item 2). Catch it here.
   [ -z "$KONNECT_TOKEN" ] && { echo "KONNECT_TOKEN empty — fill the KONNECT_PAT line in act.secrets, then re-source this block."; return 1 2>/dev/null || exit 1; }
   ```
   _Expected: no output._ The values are read by Terraform in step 4 and by the inner tree's `terracurl` data sources at plan time. If the preflight fails, populate `act.secrets` (or your equivalent secret store) before re-running.

   > **Token source — `KONNECT_TOKEN` vs `KONNECT_PAT`.** The repo's [`act.secrets`](act.secrets) template uses key name `KONNECT_PAT` (Konnect's "Personal Access Token" terminology); the Terraform input variables are `konnect_token` / `konnect_access_token` and the canonical shell name is `KONNECT_TOKEN`. The `grep`-into-`cut` form above bridges the two. If your fork has already renamed `KONNECT_PAT` → `KONNECT_TOKEN` in `act.secrets`, the portable alternative `export KONNECT_TOKEN="$(grep -E '^KONNECT_TOKEN=' act.secrets | cut -d= -f2-)"` also works on both Linux GNU `grep` and macOS BSD `grep`.

4. **Re-initialize both Terraform trees against the backend.** Each tree is initialized with an explicit `key=` backend-config override so the two trees write to **distinct** state objects in the MinIO bucket. Both [`config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend) files in the repo hard-pin `key = "konnect.tfstate"`; without the override below, the second tree's `init` would silently rebind to the first tree's state object.
   ```bash
   # Outer tree — writes to <bucket>/konnect-teams.tfstate
   (cd terraform/konnect-teams && \
     rm -rf .terraform .terraform.lock.hcl && \
     terraform init -reconfigure \
       -backend-config=config.s3.tfbackend \
       -backend-config="key=konnect-teams.tfstate" \
       -input=false -upgrade)

   # Inner tree — writes to <bucket>/provision-konnect-resources.tfstate
   (cd .github/actions/provision-konnect-resources/terraform && \
     rm -rf .terraform .terraform.lock.hcl && \
     terraform init -reconfigure \
       -backend-config=config.s3.tfbackend \
       -backend-config="key=provision-konnect-resources.tfstate" \
       -input=false -upgrade)
   ```
   _Expected: `Terraform has been successfully initialized!` in each tree; the `kong/konnect 3.15.0` plugin lands under `<tree>/.terraform/providers/registry.terraform.io/kong/konnect/3.15.0/`._ The `-reconfigure` flag is mandatory when changing backend selection or env routing (architecture pattern P1). The `-upgrade` flag re-resolves provider hashes; on a cold cache this downloads ~20-40MB per tree from the public Terraform registry.

5. **Run the migration driver.**
   ```bash
   make migrate-state
   ```
   _Expected (stderr; the driver emits all signal to stderr):_
   ```
   [migrate-state] terraform/konnect-teams: running 001-konnect-3-15-rename.sh
   [migration 001] tree=terraform/konnect-teams: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
   [migrate-state] terraform/konnect-teams: marked 001-konnect-3-15-rename.sh applied
   [migrate-state] terraform/konnect-teams: applied 1 migration(s)
   [migrate-state] .github/actions/provision-konnect-resources/terraform: running 001-konnect-3-15-rename.sh
   [migration 001] tree=.github/actions/provision-konnect-resources/terraform: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
   [migrate-state] .github/actions/provision-konnect-resources/terraform: marked 001-konnect-3-15-rename.sh applied
   [migrate-state] .github/actions/provision-konnect-resources/terraform: applied 1 migration(s)
   [migrate-state] done.
   ```
   Exit code: `0`. The driver writes a marker file at `<tree>/.terraform/migrations-applied` containing the single line `001-konnect-3-15-rename.sh` in each tree (file is gitignored via `**/.terraform/*`).

6. **Verify clean plan in both trees.**
   ```bash
   (cd terraform/konnect-teams && terraform plan -input=false -lock=false -detailed-exitcode)
   (cd .github/actions/provision-konnect-resources/terraform && terraform plan -input=false -lock=false -detailed-exitcode)
   ```
   _Expected exit codes (per Terraform's `-detailed-exitcode` contract):_
   - `0` — succeeded, diff is empty. **This is the success state for a fork with non-empty pre-3.15 state.**
   - `2` — succeeded with a diff. Acceptable **only** if every entry in the diff is a `+` (create-from-empty-state) on resources that have not yet been applied to the fork's environment. Any `~` (modify), `-/+` (replace), or `-` (destroy) entry on a resource that existed pre-bump is a real signal — see the [Rollback](#rollback) subsection below and surface to the project owner.
   - `1` — error. Two sub-cases that look identical from the exit code alone and must be disambiguated by inspecting the plan body:
     - **`1a` — 3.15.0 regression.** The plan body contains `~` / `-/+` / `-` entries on resources that existed pre-bump, AND Terraform raises a schema-validation or provider-side error. **Halt and surface to the project owner. Do not merge.**
     - **`1b` — orthogonal pre-existing error.** The plan body shows zero `~` / `-/+` / `-` lines on existing resources, but Terraform errors on a repo-state condition independent of the 3.15.0 bump (e.g., commented-out `vault` provider block in the outer tree, the inner tree's `terracurl_request "fetch_team"` against a region-mismatched or empty `KONNECT_TOKEN`, missing `TF_VAR_*` inputs). Resolve the orthogonal issue per [`_bmad-output/implementation-artifacts/deferred-work.md`](_bmad-output/implementation-artifacts/deferred-work.md) § "Deferred from: Story 1.6 verification" and re-run. **Do not treat as a 3.15.0 regression; do not roll back.**

7. **Re-run `make migrate-state` for idempotency confirmation.**
   ```bash
   make migrate-state
   ```
   _Expected (stderr):_
   ```
   [migrate-state] terraform/konnect-teams: no pending migrations (1 already applied)
   [migrate-state] .github/actions/provision-konnect-resources/terraform: no pending migrations (1 already applied)
   [migrate-state] done.
   ```
   The marker files are byte-identical before and after this re-run (verify with `shasum -a 256 <tree>/.terraform/migrations-applied`).

#### Rollback

If step 6 surfaces an unforeseen post-merge issue and the operator needs to revert provider `3.15.0` → `3.1.0`:

1. **Revert the HCL pin** in both `main.tf` files. In upstream `kw-platform-ops` (branch `new-gen`) the provider bump landed in **a single commit** — `3d574bc` (`feat: bump konnect provider to 3.15.0 and update related documentation`) — which touches both `terraform/konnect-teams/main.tf` and `.github/actions/provision-konnect-resources/terraform/main.tf` together. Related Epic 1 commits (do **not** need to be reverted for the HCL rollback; preserved for context): `b040f51` (migration driver, Story 1.5), `03c282b` (per-tree 001 migration script, Story 1.4). A fork that landed the bump differently may have one or more bump commits; discover them first, then revert each in reverse chronological order:
   ```bash
   # Find every commit on your fork that touched either main.tf
   git log --oneline -- terraform/konnect-teams/main.tf .github/actions/provision-konnect-resources/terraform/main.tf

   # Revert each provider-bump commit in reverse chronological order (newest first).
   # On a clean fork of upstream this is exactly one command:
   git revert 3d574bc
   # If your fork split the bump across multiple commits, repeat git revert for each.
   ```

2. **Re-init each tree** to drop the 3.15.0 plugin and re-resolve 3.1.0. Mirror the forward `init` from step 4 above — same per-tree `key=` overrides, same `rm -rf .terraform .terraform.lock.hcl` to clear both the cached plugin and the lockfile (the retained 3.15.0 hashes in `.terraform.lock.hcl` would otherwise conflict with the 3.1.0 re-resolution):
   ```bash
   (cd terraform/konnect-teams && \
     rm -rf .terraform .terraform.lock.hcl && \
     terraform init -reconfigure \
       -backend-config=config.s3.tfbackend \
       -backend-config="key=konnect-teams.tfstate" \
       -upgrade)

   (cd .github/actions/provision-konnect-resources/terraform && \
     rm -rf .terraform .terraform.lock.hcl && \
     terraform init -reconfigure \
       -backend-config=config.s3.tfbackend \
       -backend-config="key=provision-konnect-resources.tfstate" \
       -upgrade)
   ```

3. **Marker-file note.** The `<tree>/.terraform/migrations-applied` file retains the `001-konnect-3-15-rename.sh` line. **This is deliberately harmless**: the 001 script body is a no-op for the 3.1.0 ↔ 3.15.0 hop (per audit), so the line records "the driver visited this script" and not "state was mutated." Operators concerned about marker hygiene can `rm <tree>/.terraform/migrations-applied`; the file is gitignored and will be regenerated on the next `make migrate-state`. **No `terraform state mv` reversal is required** because no state was mutated by step 5 in the forward direction.

4. **Caveat — operator-introduced HCL on top of 3.15.0.** If the rollback is needed because the operator's fork added HCL that uses a 3.15.0-only attribute on top of the bump, that HCL must **also** be reverted; otherwise the 3.1.0 provider will fail schema validation and `init` will error out. Audit the operator's fork-local changes between the bump SHAs and HEAD before assuming the rollback recipe alone is sufficient.

## Migration 3 — Legacy provisioning workflows → Unified provisioning engine

The three fragmented Konnect provisioning workflows (`onboard-konnect-teams.yaml`,
`provision-auth-identity.yaml`, `provision-konnect-team-resources.yaml`) and
their backing Terraform trees (`terraform/konnect-teams/`,
`.github/actions/provision-konnect-resources/terraform/`) were retired in
Epic 3 (Stories 3.1–3.4) and replaced by the unified
`provision-konnect-resources.yaml` workflow reading from
`terraform/konnect/` and `konnect/orgs/<org>/*.yaml`.

**Affected:**

- Retired workflows: `.github/workflows/onboard-konnect-teams.yaml`,
  `.github/workflows/provision-auth-identity.yaml`,
  `.github/workflows/provision-konnect-team-resources.yaml`
- Retired Terraform tree: `terraform/konnect-teams/`
- Retired YAML sources: `teams/*.yaml`, `konnect/auth-identity/`,
  `konnect/teams/`, `konnect/developer-portal/`, `konnect/dashboards/`
- Retired action: `.github/actions/provision-konnect-resources/`
- Retired scripts: `scripts/validate-team-config.sh`, `scripts/run-migrations.sh`
- Retired tests: `test/provisioning/`

**Before:**

Three separate `workflow_dispatch` runs for teams, auth-identity, and per-team
resources; each backed by its own Terraform tree and per-team S3 buckets:

```bash
# Three separate dispatches required:
gh workflow run onboard-konnect-teams.yaml
gh workflow run provision-auth-identity.yaml
gh workflow run provision-konnect-team-resources.yaml --field team=flight-operations
```

Resource YAML lived in `teams/*.yaml`, `konnect/auth-identity/`, `konnect/teams/`,
`konnect/developer-portal/`, and `konnect/dashboards/` — spread across five
directories with different schemas.

**After:**

One `provision-konnect-resources.yaml` workflow dispatch:

```yaml
# .github/workflows/provision-konnect-resources.yaml
on:
  workflow_dispatch:
    inputs:
      org: { default: 'konnect', type: string }
      action: { default: 'plan', type: choice, options: [plan, apply, destroy] }
```

```bash
# Single dispatch covering all Konnect resources:
gh workflow run provision-konnect-resources.yaml \
  --field org=konnect \
  --field action=apply
```

All Konnect resource declarations live under `konnect/orgs/<org>/*.yaml`.
State is managed under a single bucket key: `konnect/orgs/<org>/terraform.tfstate`.

**Remediation:**

1. **Update fork CI pipelines** that called the three retired workflows to instead
   dispatch `.github/workflows/provision-konnect-resources.yaml`:
   ```yaml
   # Replace any reference to the three legacy workflows with:
   uses: ./.github/workflows/provision-konnect-resources.yaml
   with:
     org: konnect
     action: apply
   ```

2. **Migrate resource YAML** from legacy source directories into `konnect/orgs/<org>/`
   following the top-level key schema in `konnect/orgs/konnect/*.yaml` as the reference.
   Key mapping:
   - `teams/<name>.yaml` → entries in `konnect/orgs/<org>/teams.yaml`
   - `konnect/auth-identity/` → `konnect/orgs/<org>/authentication-settings.yaml` + `identity-provider.yaml`
   - `konnect/teams/<name>/resources.yaml` → control-plane and role entries in `konnect/orgs/<org>/control-planes.yaml`
   - `konnect/developer-portal/config.yaml` → `konnect/orgs/<org>/portals.yaml`
   - `konnect/dashboards/` → `konnect/orgs/<org>/dashboards.yaml`

3. **Initialize the unified Terraform root** against the new backend key:
   ```bash
   cd terraform/konnect
   terraform init -reconfigure \
     -backend-config=config.minio.tfbackend \
     -backend-config="key=konnect/orgs/konnect/terraform.tfstate"
   ```
   No `terraform state mv` is required when starting from a clean state. If
   migrating existing state from the legacy trees, import resources individually
   via `terraform import` — the unified module uses the same provider resource
   types (`konnect_team`, `konnect_control_plane`, etc.) so attribute mappings are
   straightforward.

4. **Remove legacy `migrate-state` references.** The `Makefile` `migrate-state`
   target and `scripts/run-migrations.sh` have been retired alongside the legacy trees.
   Scan your fork for any remaining references and remove them:
   ```bash
   # Find remaining references in CI workflows and scripts
   grep -r "migrate-state\|run-migrations" .github/ scripts/ Makefile 2>/dev/null
   ```

   Delete or comment out any lines that invoke:
   - `make migrate-state` — the Makefile target no longer exists; calling it will error.
   - `bash scripts/run-migrations.sh` (or `./scripts/run-migrations.sh`) — the file is deleted.
   - Any workflow step with `run: make migrate-state` or a reference to `scripts/run-migrations.sh`.

   **Before** (example fork CI step to remove):
   ```yaml
   - name: Run state migrations
     run: make migrate-state
   ```
   **After:** delete the step entirely. The unified Terraform root manages its own state
   from first `init`; there are no pre-apply migration scripts.
