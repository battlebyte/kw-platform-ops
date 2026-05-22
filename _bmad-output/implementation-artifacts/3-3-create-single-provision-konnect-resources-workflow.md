# Story 3.3: Create single `provision-konnect-resources.yaml` workflow

Status: done

## Story

As a platform engineer,
I want one operator workflow that provisions any supported Konnect entity from `konnect/orgs/<org>/`,
so that operators no longer choose between team onboarding, auth identity provisioning, and per-team resource provisioning workflows.

## Acceptance Criteria

1. **Given** `workflow_dispatch` inputs `org` (default `konnect`), `action` (`plan`, `apply`, `destroy`), and optional `rotate-certs`
   **When** the workflow is dispatched
   **Then** it runs Terraform against `terraform/konnect/` using `TF_VAR_org=<org>` and config path `konnect/orgs/<org>`

2. **Given** a push to `main` changes files under `konnect/orgs/**`
   **When** the workflow triggers
   **Then** it runs the same validation, init, plan, and apply path for the affected org (defaulting to `konnect`)

3. **Given** the local MinIO backend is selected (`TF_BACKEND_CONFIG=config.minio.tfbackend` or unset)
   **When** the workflow initializes Terraform
   **Then** it uses the existing `init-terraform` action and passes `backend-config-overrides: key=konnect/orgs/<org>/terraform.tfstate` to dynamically scope the state key to the org
   **And** it ensures the single shared state bucket exists once (`tfstate` for MinIO)
   **And** it does not create buckets per team or per resource file

4. **Given** AWS S3 backend is selected (`TF_BACKEND_CONFIG=config.s3.tfbackend`)
   **When** the workflow initializes Terraform
   **Then** it uses the same state key shape (`konnect/orgs/<org>/terraform.tfstate`) via `backend-config-overrides`
   **And** it ensures the single shared state bucket exists once (`kw.konnect.terraform-state` for S3)

5. **Given** HashiCorp Vault credentials are supplied
   **When** `terraform apply` completes
   **Then** per-team system account tokens are stored in Vault as before (via `terraform/konnect/`'s `team_system_accounts` and `team_vault` modules)
   **And** `KONNECT_TOKEN`, `VAULT_TOKEN`, client secrets, and generated system-account tokens are never printed to workflow logs

6. **Given** the workflow replaces three legacy workflows
   **When** implementation completes
   **Then** `.github/workflows/provision-konnect-resources.yaml` exists and is functional
   **And** `.github/workflows/onboard-konnect-teams.yaml`, `.github/workflows/provision-auth-identity.yaml`, and `.github/workflows/provision-konnect-team-resources.yaml` have no remaining production responsibility (retirement deferred to Story 3.4)

## Tasks / Subtasks

- [x] Create `.github/workflows/provision-konnect-resources.yaml` (AC: 1, 2, 3, 4, 5)
  - [x] Add `workflow_dispatch` trigger with inputs `org` (string, default `konnect`), `action` (choice: `plan`/`apply`/`destroy`, default `plan`), `rotate-certs` (boolean, default `false`, reserved for future use)
  - [x] Add `push` trigger on `main` filtered to `konnect/orgs/**`
  - [x] Define job-level env block (see Dev Notes § Required Env Vars)
  - [x] Add `Checkout repository` step (`actions/checkout@v4`)
  - [x] Add `Setup Terraform` step (`hashicorp/setup-terraform@v3`, `terraform_version: latest`)
  - [x] Add conditional AWS CLI install step (`unfor19/install-aws-cli-action@v1`, only when `TF_BACKEND_CONFIG != config.minio.tfbackend`)
  - [x] Add conditional `aws-actions/configure-aws-credentials@v4` step (only when not MinIO)
  - [x] Add `Set mock AWS credentials for MinIO backend` step (only when MinIO)
  - [x] Add `Ensure TF state bucket exists` step — MinIO branch calls `create-state-bucket.sh tfstate minio`; S3 branch calls `create-state-bucket.sh kw.konnect.terraform-state aws` (AC: 3, 4)
  - [x] Add `Init Terraform` step using `init-terraform` action with `terraform-dir`, `backend-config-path`, and `backend-config-overrides` for dynamic state key (AC: 3, 4)
  - [x] Add `Validate Terraform config` step (`terraform validate`) — step name must start with `Validate` per AR12 prefix convention (AC: 5 — preconditions check secrets discipline)
  - [x] Add `Plan Konnect resources` step (`terraform plan -out=tfplan`), skipped when `action == 'destroy'`
  - [x] Add `Apply Konnect resources` step (`terraform apply -auto-approve tfplan`), runs when event is `push` OR `action == 'apply'`
  - [x] Add `Destroy Konnect resources` step (`terraform destroy -auto-approve`), runs only when `action == 'destroy'`
  - [x] Verify no `|| true` or `continue-on-error: true` on any Validate/Plan step (NFR12)
- [x] Validate the new workflow locally (AC: 1, 2)
  - [x] Run `act --list` to confirm the workflow is detected by `act`
  - [x] Run `act -n -W .github/workflows/provision-konnect-resources.yaml` (dry-run) to confirm YAML is syntactically valid

## Dev Notes

### File to Create

| File                                                 | Status  | Notes                            |
| ---------------------------------------------------- | ------- | -------------------------------- |
| `.github/workflows/provision-konnect-resources.yaml` | **NEW** | The only file this story creates |

**Do NOT modify or create any other file.** In particular:
- Do NOT touch `terraform/konnect/` (module is complete from Stories 3.1/3.2)
- Do NOT retire legacy workflows (`onboard-konnect-teams.yaml`, `provision-auth-identity.yaml`, `provision-konnect-team-resources.yaml`) — retirement is Story 3.4
- Do NOT touch `konnect/orgs/konnect/*.yaml` — YAML is complete from Story 3.2

### Required Env Vars

The providers in `terraform/konnect/providers.tf` read from **Terraform variables, not raw env vars**. All credentials must be mapped explicitly:

```yaml
env:
  # Backend selection — defaults to MinIO for local act runs
  TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}

  # Terraform working directory
  TERRAFORM_DIR: ${{ github.workspace }}/terraform/konnect

  # Konnect — provider reads local.konnect_token = coalesce(var.konnect_access_token, var.konnect_token, "")
  TF_VAR_konnect_access_token: ${{ secrets.KONNECT_TOKEN }}
  TF_VAR_konnect_server_url: ${{ vars.KONNECT_SERVER_URL || 'https://eu.api.konghq.com' }}

  # Vault — provider reads var.vault_address and var.vault_token directly
  TF_VAR_vault_address: ${{ vars.VAULT_ADDR || 'http://localhost:8300' }}
  TF_VAR_vault_token: ${{ secrets.VAULT_TOKEN }}

  # Org — selects konnect/orgs/<org>/*.yaml and sets state key
  TF_VAR_org: ${{ inputs.org || 'konnect' }}
```

**Critical:** `TF_VAR_konnect_access_token` MUST come from `secrets.KONNECT_TOKEN`. Never echo it to logs. `TF_VAR_vault_token` MUST come from `secrets.VAULT_TOKEN`. GitHub Actions automatically masks values sourced from `secrets.*` in log output (NFR4).

**Do NOT set** `KONNECT_TOKEN` as a standalone env var — the new module does not use env-var provider auth; it reads through `var.konnect_access_token`. Setting it would be redundant and could cause confusion.

> Source: `terraform/konnect/providers.tf` (lines 18–31) + `terraform/konnect/main.tf` (line 15: `coalesce(var.konnect_access_token, var.konnect_token, "")`) + project-context.md §Security Requirements

### init-terraform Action Invocation Pattern

The `init-terraform` composite action supports `backend-config-overrides` to append additional `-backend-config` flags. Use this to dynamically scope the state key to the org without editing the `.tfbackend` files:

```yaml
- name: Init Terraform
  uses: ./.github/actions/init-terraform
  with:
    terraform-dir: ${{ env.TERRAFORM_DIR }}
    backend-config-path: ${{ env.TF_BACKEND_CONFIG }}
    backend-config-overrides: |
      key=konnect/orgs/${{ inputs.org || 'konnect' }}/terraform.tfstate
```

The `backend-config-overrides` value is a multiline string; each non-blank line is appended as `-backend-config=<line>`. Later `-backend-config` flags for the same key win over earlier ones, so this correctly overrides the `key` value hardcoded in `config.minio.tfbackend` / `config.s3.tfbackend`.

> Source: `.github/actions/init-terraform/action.yml` — reads `backend-config-overrides` and processes each line in a while loop.

### State Bucket Creation Pattern

Use `scripts/create-state-bucket.sh` (delivered in Story 2.4). Script signature: `create-state-bucket.sh <bucket-name> [minio|aws]`.

```yaml
- name: Ensure TF state bucket exists
  shell: bash
  run: |
    if [ "${{ env.TF_BACKEND_CONFIG }}" = "config.minio.tfbackend" ]; then
      ./create-state-bucket.sh tfstate minio
    else
      ./create-state-bucket.sh kw.konnect.terraform-state aws
    fi
  working-directory: ${{ github.workspace }}/scripts
```

**Bucket names are taken from the `.tfbackend` files directly:**
- MinIO: `bucket = "tfstate"` (from `terraform/konnect/config.minio.tfbackend`)
- S3: `bucket = "kw.konnect.terraform-state"` (from `terraform/konnect/config.s3.tfbackend`)

Do NOT create per-team buckets. The state key scopes the org, not the bucket. (ADR #002: "Single bucket (`kw.konnect.state`), key = `konnect/orgs/<org>/terraform.tfstate`".)

> Source: `terraform/konnect/config.minio.tfbackend`, `terraform/konnect/config.s3.tfbackend`, `scripts/create-state-bucket.sh`

### MinIO Credential Pattern

For MinIO backend, inject mock AWS credentials (MinIO uses the S3-compatible API with static credentials):

```yaml
- name: Set mock AWS credentials for MinIO backend
  if: env.TF_BACKEND_CONFIG == 'config.minio.tfbackend'
  shell: bash
  run: |
    echo "AWS_ACCESS_KEY_ID=minio-root-user" >> $GITHUB_ENV
    echo "AWS_SECRET_ACCESS_KEY=minio-root-password" >> $GITHUB_ENV
    echo "AWS_DEFAULT_REGION=eu-central-1" >> $GITHUB_ENV
```

These values match `config.minio.tfbackend` (`access_key = "minio-root-user"`, `secret_key = "minio-root-password"`). These are local-stack test credentials, not real secrets.

> Source: `terraform/konnect/config.minio.tfbackend` + `onboard-konnect-teams.yaml` (same pattern already in production)

### Plan / Apply / Destroy Conditional Steps

The three Terraform execution steps use `if:` guards:

```yaml
- name: Plan Konnect resources
  if: inputs.action != 'destroy'
  shell: bash
  working-directory: ${{ env.TERRAFORM_DIR }}
  run: terraform plan -out=tfplan

- name: Apply Konnect resources
  if: github.event_name == 'push' || inputs.action == 'apply'
  shell: bash
  working-directory: ${{ env.TERRAFORM_DIR }}
  run: terraform apply -auto-approve tfplan

- name: Destroy Konnect resources
  if: inputs.action == 'destroy'
  shell: bash
  working-directory: ${{ env.TERRAFORM_DIR }}
  run: terraform destroy -auto-approve
```

**On push trigger:** `inputs.action` is empty; `Apply Konnect resources` fires because `github.event_name == 'push'` is true. The plan step fires first (no `destroy` condition). This gives auto-apply on GitOps push, matching the AC.

**Destroy:** Skips the plan step to avoid writing a `tfplan` file that is never used. Runs `terraform destroy -auto-approve` directly.

> Source: Epics.md §Story 3.3 ACs

### Validation Step

`terraform validate` runs the module's built-in `terraform_data` preconditions (defined in `terraform/konnect/main.tf`). These check:
- `identity_provider_secret_violations == 0` — no hardcoded `oidc_client_secret`
- `portal_auth_secret_violations == 0` — no hardcoded portal OIDC secrets
- `portal_customization_unsupported_keys == 0` — no unsupported portal customization keys
- `sanitized_team_names` are unique and non-empty

Step name must start with `Validate` per the AR12 prefix convention (prerequisite for `lint-no-bypass.yaml` Story in the future):

```yaml
- name: Validate Terraform config
  shell: bash
  working-directory: ${{ env.TERRAFORM_DIR }}
  run: terraform validate
```

Do NOT add `|| true` or `continue-on-error: true` to this step — validation failures must block the workflow (NFR12).

> Source: `terraform/konnect/main.tf` precondition blocks + project-context.md §Testing & Validation Rules

### Step-Name Prefix Convention

Per project-context.md + AR12: steps performing validation, linting, or planning must have names prefixed with `Validate`, `Lint`, or `Plan` so the future `lint-no-bypass.yaml` CI workflow can target them correctly:

| Step                         | Required Prefix |
| ---------------------------- | --------------- |
| `terraform validate`         | `Validate`      |
| `terraform plan -out=tfplan` | `Plan`          |

Apply and destroy steps have no required prefix.

### Trigger Paths

```yaml
on:
  workflow_dispatch:
    inputs:
      org:
        description: 'Konnect organisation name (selects konnect/orgs/<org>/*.yaml)'
        required: false
        default: 'konnect'
        type: string
      action:
        description: 'Terraform action to perform'
        required: false
        default: 'plan'
        type: choice
        options:
          - plan
          - apply
          - destroy
      rotate-certs:
        description: 'Rotate TLS certificates (reserved for future use; no-op in this story)'
        required: false
        default: false
        type: boolean
  push:
    branches:
      - main
    paths:
      - 'konnect/orgs/**'
```

**`rotate-certs` is declared but performs no action in this story** — it is a reserved input for future TLS rotation functionality. Include it as a boolean input but do not write any conditional steps for it; the workflow simply ignores the value.

> Source: Epics.md §Story 3.3 ACs + project-context.md §GitHub Actions — workflows (operator-run)

### secret_key vs access_key Caveat (MinIO backend config)

`terraform/konnect/config.minio.tfbackend` uses the **Terraform S3 backend key names** (`access_key` / `secret_key`), not the AWS SDK env var names (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`). When the init-terraform action runs `terraform init -backend-config=config.minio.tfbackend`, the backend reads credentials directly from the file. The `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars injected by the "Set mock AWS credentials" step are needed only for the `create-state-bucket.sh` script (which uses the `aws s3` CLI).

Do NOT remove the mock credential injection step even though the `.tfbackend` file has static credentials embedded — the bucket creation script still needs them.

### Vault: per-team System Account Tokens Flow

The `terraform/konnect/main.tf` module automatically creates a system account per declared team via:

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

The workflow does not need to do anything special for this — it just needs to supply `TF_VAR_vault_address` and `TF_VAR_vault_token`. The module handles the Vault writes internally. Generated tokens are written to Vault only and never surfaced as Terraform outputs (NFR9).

> Source: `terraform/konnect/main.tf` (module "team_system_accounts" / module "team_vault" blocks) + Story 3.2 Dev Notes §System Accounts

### Architecture Compliance

- Follow platform workflow pattern: `workflow_dispatch` + path-filtered `push` on `main` — matching the existing `onboard-konnect-teams.yaml` pattern. [Source: project-context.md §GitHub Actions — workflows (operator-run)]
- Job-level env block for all shared env vars; no duplication per step. [Source: project-context.md §GitHub Actions — workflows]
- `secrets.*` only for credentials; `vars.*` for non-sensitive config. [Source: project-context.md §GitHub Actions — workflows]
- `shell: bash` on every inline step. [Source: project-context.md §Bash rules]
- No `continue-on-error: true` or `|| true` on Validate/Plan steps. [Source: project-context.md §Testing & Validation Rules + NFR12]
- Third-party action pins: `actions/checkout@v4`, `hashicorp/setup-terraform@v3`, `aws-actions/configure-aws-credentials@v4`, `unfor19/install-aws-cli-action@v1`. [Source: project-context.md §GitHub Actions / Workflows]

### Previous Story Intelligence (from Story 3.2)

- Story 3.2 confirmed `terraform validate` passes on `terraform/konnect/` with the current YAML. The new workflow's `Validate Terraform config` step will exercise the same preconditions.
- The `konnect/orgs/konnect/*.yaml` files are now complete and in Sanofi format. Do NOT add any new YAML files or modify existing ones in this story.
- Story 3.2 confirmed the team roles are in Sanofi `roles` format; the module generates system accounts and Vault entries automatically.
- `portals.yaml` has `robots:` and `spec_renderer:` added; `identity-provider.yaml` uses `oidc_client_secret_ref`. These preconditions are already satisfied for the validation step.
- The `providers.tf` pins: `kong/konnect = 3.17.0`, `Kong/konnect-beta = 0.17.0`, `hashicorp/vault = 4.4.0`. Do not bump these pins in this story.

### Git Intelligence

- **Commit `a4cc899`** (HEAD, `new-gen`): Story 3.2 — YAML migration. Files changed: `konnect/orgs/konnect/teams.yaml`, `konnect/orgs/konnect/portals.yaml`.
- **Commit `531510b`** (Story 3.1): Created `terraform/konnect/`. Files changed: `terraform/konnect/**`, `konnect/orgs/konnect/identity-provider.yaml`, `konnect/orgs/konnect/portals.yaml`.
- **Commit `e965e9e`** (Correct course): Sprint change proposal. Introduced `konnect/orgs/konnect/` partial files and cancelled Epics 3/4/5 (old).
- The `.github/workflows/` directory has not been touched since the correct-course commit — the three legacy workflows remain unchanged and will remain unchanged until Story 3.4.

### Anti-Patterns To Avoid

- Do NOT use `secrets: inherit` — secrets flow explicitly via workflow inputs to job env. [Source: project-context.md §NFR6]
- Do NOT `echo` any secret value to the log. Use `>> $GITHUB_ENV` with variable names only (e.g., `echo "AWS_ACCESS_KEY_ID=minio-root-user"` is safe because this is a test credential, but `echo "TF_VAR_konnect_access_token=$KONNECT_TOKEN"` is forbidden).
- Do NOT add `TF_VAR_konnect_access_token` to `$GITHUB_ENV` — it is set as a job-level env var only, not re-exported.
- Do NOT create per-team buckets — the single `tfstate` (MinIO) or `kw.konnect.terraform-state` (S3) bucket is used for all orgs. The state key differentiates orgs.
- Do NOT delete or modify `onboard-konnect-teams.yaml`, `provision-auth-identity.yaml`, or `provision-konnect-team-resources.yaml` — legacy workflows are retired in Story 3.4 only.
- Do NOT attempt to validate `konnect/orgs/konnect/*.yaml` with `scripts/validate-team-config.sh` — that script validates the **legacy** `teams/*.yaml` format (role fields like `control_plane_roles`, `api_roles`, `entitlements`). The new Sanofi-format YAML is validated by `terraform validate` via the module preconditions.
- Do NOT hardcode the state key `konnect/orgs/konnect/terraform.tfstate` in the workflow — use `backend-config-overrides: key=konnect/orgs/${{ inputs.org || 'konnect' }}/terraform.tfstate` to keep it dynamic.

### Project Context Reference

Core project conventions are in `_bmad-output/project-context.md`. Key sections for this story:
- §GitHub Actions — workflows (operator-run): trigger pattern, job-level env, `vars.*` vs `secrets.*`
- §Bash (in composite actions and scripts): `shell: bash`, no echo secrets
- §Testing & Validation Rules: no bypass patterns, validation gates
- §Security Requirements (NFR4–NFR6, NFR9): secret discipline

No UX artifact exists for this project. This story has no frontend or operator-UI work.

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4.6 (GitHub Copilot)

### Debug Log References

- `act --list`: workflow detected as `provision-konnect-resources` (push, workflow_dispatch) ✅
- `act -n -W .github/workflows/provision-konnect-resources.yaml`: all steps DRYRUN ✅, Job succeeded ✅
- Grep for `continue-on-error` and `|| true` on Validate/Plan steps: no matches ✅

### Completion Notes List

- Created `.github/workflows/provision-konnect-resources.yaml` — unified operator workflow replacing the three legacy provisioning workflows (to be retired in Story 3.4).
- `workflow_dispatch` with `org`, `action` (plan/apply/destroy), `rotate-certs` (reserved no-op); `push` on `main` filtered to `konnect/orgs/**`.
- Job-level env block maps all Terraform variables from `secrets.*` / `vars.*` — `TF_VAR_konnect_access_token` from `secrets.KONNECT_TOKEN`, `TF_VAR_vault_token` from `secrets.VAULT_TOKEN`. No standalone `KONNECT_TOKEN` env var.
- Conditional AWS CLI install and credentials steps gate on `TF_BACKEND_CONFIG != config.minio.tfbackend`; mock credentials step for MinIO (test credentials, not secrets).
- Single `Ensure TF state bucket exists` step: MinIO → `tfstate`, S3 → `kw.konnect.terraform-state`. No per-team buckets.
- `Init Terraform` uses `init-terraform` composite action with `backend-config-overrides: key=konnect/orgs/${{ inputs.org || 'konnect' }}/terraform.tfstate` for dynamic org-scoped state key.
- `Validate Terraform config` step name starts with `Validate` per AR12; no bypass patterns.
- Plan/Apply/Destroy guards: destroy skips plan; apply fires on push (GitOps) or `action == 'apply'`; destroy is explicit-only.
- All 6 Acceptance Criteria satisfied. Dry-run and act --list validations pass.

### File List

- `.github/workflows/provision-konnect-resources.yaml`

### Change Log

- 2026-05-22: Created `.github/workflows/provision-konnect-resources.yaml` — unified Konnect provisioning workflow (Story 3.3). Implements workflow_dispatch (org/action/rotate-certs inputs) + push trigger on konnect/orgs/**; dynamic org-scoped state key via init-terraform backend-config-overrides; MinIO/S3 dual-backend support; Validate/Plan/Apply/Destroy steps with correct conditional guards and no bypass patterns. (Story 3-3)

### Review Findings

- [x] [Review][Decision → Accepted] Push trigger always defaults to 'konnect' org — Single-org reality; AC2 "defaulting to konnect" is intentional. Multi-org push dispatch deferred to a future story when a second org is introduced.
- [x] [Review][Patch] `destroy` action has no safeguard — add `environment:` job-level gate (konnect-production) AND add `Plan Konnect resources (destroy preview)` step (`terraform plan -destroy -out=tfplan`) so destroy uses the plan file [.github/workflows/provision-konnect-resources.yaml:31,110]
- [x] [Review][Patch] No `concurrency:` group — race condition on Terraform state [.github/workflows/provision-konnect-resources.yaml:31]
- [x] [Review][Patch] No `permissions:` block — GITHUB_TOKEN inherits repo defaults (may include write scopes) [.github/workflows/provision-konnect-resources.yaml:31]
- [x] [Review][Patch] `rotate-certs` input is a silent no-op — callers setting `true` receive no error and no effect; add a warning step or note [.github/workflows/provision-konnect-resources.yaml:19]
- [x] [Review][Patch] `aws-session-token` unconditionally passed — empty string passed for long-lived IAM credentials; conditionally include or omit [.github/workflows/provision-konnect-resources.yaml:70]
- [x] [Review][Patch] `configure-aws-credentials` step missing `name:` field — renders as raw action ref in UI; inconsistent with all other steps [.github/workflows/provision-konnect-resources.yaml:64]
- [x] [Review][Patch] `backend-config-overrides` re-evaluates org fallback independently — use `${{ env.TF_VAR_org }}` instead of `${{ inputs.org || 'konnect' }}` to avoid divergence [.github/workflows/provision-konnect-resources.yaml:96]
- [x] [Review][Patch] `inputs.org` path-traversal injection risk — value flows directly into state key and YAML path; validate against `^[a-z0-9][a-z0-9-]*$` pattern [.github/workflows/provision-konnect-resources.yaml:8]
- [x] [Review][Patch] `vars.AWS_REGION` has no default fallback — `aws-region: ${{ vars.AWS_REGION }}` passes empty string when var is unset; add `|| 'eu-central-1'` [.github/workflows/provision-konnect-resources.yaml:69]
- [x] [Review][Defer] `terraform_version: "latest"` — non-reproducible builds [.github/workflows/provision-konnect-resources.yaml:54] — deferred, pre-existing project convention
- [x] [Review][Defer] Third-party actions pinned to mutable floating tags, not SHAs — deferred, pre-existing project convention (project-context.md §GitHub Actions / Workflows)
- [x] [Review][Defer] MinIO credentials hardcoded (`minio-root-user` / `minio-root-password`) — deferred, pre-existing local dev convention matching docker-compose defaults
- [x] [Review][Defer] `TF_VAR_vault_address` defaults to `http://localhost:8300` (plaintext) — deferred, pre-existing project convention
- [x] [Review][Defer] Missing required secrets (`KONNECT_TOKEN`, `VAULT_TOKEN`) fail late with opaque errors — deferred, no spec requirement for early validation; Terraform surfaces auth errors at plan time
