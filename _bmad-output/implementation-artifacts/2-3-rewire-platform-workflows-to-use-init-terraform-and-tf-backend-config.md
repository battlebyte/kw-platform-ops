# Story 2.3: Rewire platform workflows to use `init-terraform` and `TF_BACKEND_CONFIG`

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want every platform workflow that performs Terraform operations to call the shared `init-terraform` action with `TF_BACKEND_CONFIG` controlling backend selection,
So that backend selection is uniform across the workflow surface and `act`-driven local runs default to MinIO without hand-edits.

## Acceptance Criteria

### AC1 — `init-terraform` gains a `backend-config-overrides` input (additive, non-breaking)

**Given** [`.github/actions/init-terraform/action.yml`](.github/actions/init-terraform/action.yml) and its [`README.md`](.github/actions/init-terraform/README.md) (Story 2.2 deliverables)
**When** I extend the action with one new optional input `backend-config-overrides` (multiline string, default empty)
**Then** [`.github/actions/init-terraform/action.yml`](.github/actions/init-terraform/action.yml) declares the input with `required: false`, `default: ''`, and a description naming its purpose ("one `key=value` per line; each line is appended as an additional `-backend-config="<line>"` flag")
**And** the action body, while preserving the verbatim `terraform init -reconfigure -input=false -upgrade -backend-config="${{ inputs.backend-config-path }}"` invocation, additionally appends `-backend-config="<line>"` once per non-blank line read from `inputs.backend-config-overrides` — implemented in Bash via a `while IFS= read -r override; do [[ -z "$override" ]] && continue; cmd+=(-backend-config="$override"); done <<< "${{ inputs.backend-config-overrides }}"` pattern, with the final `terraform init` invoked as `"${cmd[@]}"`
**And** [`.github/actions/init-terraform/README.md`](.github/actions/init-terraform/README.md) is updated: the `## Inputs` table gains a third row for `backend-config-overrides` (description, `no`, `''`); the `## Example Usage` AWS block is updated to show a realistic multiline override (`bucket=<name>\nregion=<region>`); the `## Failure Modes` section gains one new entry covering "blank-line / malformed `key=value` in overrides" → "lines with no `=` are still passed through; Terraform surfaces them as `Invalid -backend-config` errors"
**And** the P4 H2 sections (`Overview`, `Inputs`, `Outputs`, `Side Effects`, `Example Usage`, `Failure Modes`) remain in canonical order with no additions or omissions; the `## Outputs` body remains `_None._`
**And** a post-write parity check passes: every input listed in `action.yml`'s `inputs:` keys appears as a row in the README `## Inputs` table with matching name, `required` flag, and default

### AC2 — Outer tree's `config.s3.tfbackend` bakes the static AWS values for the canonical workflow

**Given** [`terraform/konnect-teams/config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend) (the outer-tree AWS backend-config file, currently using placeholder `bucket = "tfstate"` / `region = "main"` because the workflow overrides them inline)
**When** I edit the file so `bucket = "kw.konnect.teams"`, `region = "eu-central-1"`, and `key = "konnect.tfstate"`
**Then** the file is fully self-sufficient for the outer workflow's AWS path with no dynamic `-backend-config="bucket=…"` overrides at the call site
**And** the other backend-config keys (`use_path_style`, `encrypt`, `skip_*`) remain unchanged
**And** the file is annotated with a top-comment block matching the style of `config.minio.tfbackend` (purpose, paired-file note, init incantation example)
**And** **the inner tree's** [`.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend) is **NOT** baked with a static bucket — bucket is per-team and must remain caller-overridden (handled by AC4's `backend-config-overrides` plumbing). The inner file's existing placeholder shape stays.
**And** both `config.minio.tfbackend` files (Story 2.1 deliverables) are **untouched** — byte-identical pre/post (verifiable via `shasum -a 256`)

### AC3 — `onboard-konnect-teams.yaml` is rewired to `init-terraform` + `TF_BACKEND_CONFIG`

**Given** [`.github/workflows/onboard-konnect-teams.yaml`](.github/workflows/onboard-konnect-teams.yaml) (currently inlines `terraform init` at lines 116-124 with dynamic `-backend-config="bucket=…"` overrides, sets `AWS_S3_BUCKET` env at line 30, and unconditionally runs `create-s3-bucket.sh` at line 110-114)
**When** I rewire the workflow per the following exact deltas:
1. **Add** a job-level env entry `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` (inserted alongside the existing job-level env at lines 18-30).
2. **Keep** the `AWS_S3_BUCKET: "kw.konnect.teams"` job-level env entry — it is still consumed by the gated bucket-creation step below. The duplication with the bucket name now baked into `config.s3.tfbackend` is transitional; Story 2.4's `create-state-bucket.sh` will collapse it.
3. **Gate** the `Ensure TF state S3 bucket exists` step (lines 110-114) with `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'`. The `./create-s3-bucket.sh ${{ env.AWS_S3_BUCKET }}` invocation is **left unchanged** — the rename to `create-state-bucket.sh` is Story 2.4 territory.
4. **Replace** the `Terraform Init` step (lines 116-124) with `uses: ./.github/actions/init-terraform` + `with: { terraform-dir: ${{ env.TERRAFORM_DIR }}, backend-config-path: ${{ env.TF_BACKEND_CONFIG }} }`. Do **not** pass `backend-config-overrides` (outer workflow does not need overrides — bucket/region/key are baked into `config.s3.tfbackend` per AC2 and into `config.minio.tfbackend` per Story 2.1).
5. Preserve the step `name:` text on the new `uses:` step as `Terraform Init` (P3 prefix convention is N/A for init; keeping the same name preserves grep-discoverability and git-history continuity).
**Then** the workflow no longer contains any inline `terraform init` invocation (verifiable: `grep -n 'terraform init' .github/workflows/onboard-konnect-teams.yaml` returns no matches)
**And** the workflow contains exactly one `uses: ./.github/actions/init-terraform` invocation
**And** the step ordering is preserved: Checkout → Setup Terraform → Install AWS CLI → Configure AWS Credentials → Validate config → (gated) Ensure TF state S3 bucket exists → Terraform Init (via action) → Terraform Plan → Terraform Apply
**And** the `Validate config`, `Terraform Plan`, and `Terraform Apply` steps are **untouched**

### AC4 — `provision-konnect-resources/action.yaml` is rewired to `init-terraform` with per-team overrides

**Given** [`.github/actions/provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml) (currently inlines `terraform init` at lines 109-116 with `bucket=kw.konnect.team.resources.${{ inputs.konnect-team-name }}` and `region=${{ inputs.aws-region }}` overrides)
**When** I rewire the action per the following exact deltas:
1. **Replace** the `Terraform Init` step (lines 109-116) with `uses: ./.github/actions/init-terraform` + `with: { terraform-dir: ${{ github.action_path }}/terraform, backend-config-path: ${{ env.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}, backend-config-overrides: "bucket=kw.konnect.team.resources.${{ inputs.konnect-team-name }}\nregion=${{ inputs.aws-region }}" }`.
   - The `backend-config-overrides` value uses a YAML literal-block scalar (`|`) so the two `key=value` lines are passed verbatim with a newline separator.
2. Preserve the step `name:` as `Terraform Init` on the new `uses:` step.
3. The `Setup Terraform Environment` step (lines 83-107), `Validate config` step (lines 78-81), `Setup Terraform` (lines 73-76), `Install yq` (lines 57-71), and the three Terraform Plan/Apply/Destroy steps (lines 118-143) are **untouched**.
**Then** the action no longer contains any inline `terraform init` invocation
**And** the action's `inputs:` declarations are **untouched** (no contract change — the action's caller-facing API is identical pre and post)
**And** the action depends on the caller (e.g., `developer-portal.yaml`) having `TF_BACKEND_CONFIG` set at job-level env so the env-inheritance reaches this composite action

### AC5 — `developer-portal.yaml` propagates `TF_BACKEND_CONFIG` to the inner action

**Given** [`.github/workflows/developer-portal.yaml`](.github/workflows/developer-portal.yaml) (currently sets `AWS_S3_BUCKET` job-level env for the `Ensure TF state S3 bucket exists` step at line 54-58, then calls `provision-konnect-resources` action which does its own `terraform init`)
**When** I rewire the workflow per the following exact deltas:
1. **Add** a job-level env entry `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` (inserted alongside the existing env block at lines 26-38).
2. **Gate** the `Ensure TF state S3 bucket exists` step (lines 54-58) with `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'` (script rename to `create-state-bucket.sh` is Story 2.4 territory; leave the current invocation in place).
3. **Do NOT remove** the `AWS_S3_BUCKET: "kw.konnect.dev-portal-terraform-state"` env entry — it's still consumed by the gated `create-s3-bucket.sh` step. (Note: this bucket name does **not** match the inner action's per-team bucket pattern; that pre-existing mismatch is out-of-scope for Story 2.3 and is documented in Dev Notes.)
4. The `Provision Konnect Developer Portal resources` step (lines 60-77) is **untouched** — the inner `provision-konnect-resources` action picks up `TF_BACKEND_CONFIG` from the job-level env automatically.
**Then** the workflow declares `TF_BACKEND_CONFIG` at job level
**And** the workflow's `uses: ./.github/actions/provision-konnect-resources` invocation is byte-identical pre and post

### AC6 — End-to-end MinIO verification via `act` against `onboard-konnect-teams.yaml`

**Given** the local docker-compose stack is running (`docker compose up -d minio minio-create-bucket vault`) and the `tfstate` bucket is reachable (curl `http://localhost:9000/tfstate` returns `200` or `403`)
**And** `act.secrets` exists at the repo root with a valid `KONNECT_TOKEN` for the EU production Konnect tenant (or the operator-supplied test tenant)
**And** [`.actrc.tpl`](.actrc.tpl)-derived `.actrc` is in place (or `--network host` is passed explicitly)
**And** the canonical [`teams/flight-operations.yaml`](teams/flight-operations.yaml) fixture exists with valid `name`, `entitlements`, and `default_role` fields
**When** I run:
```bash
act -W .github/workflows/onboard-konnect-teams.yaml \
    --network host \
    --secret-file act.secrets \
    workflow_dispatch
```
without setting `TF_BACKEND_CONFIG` (so it defaults to `config.minio.tfbackend`)
**Then** the workflow runs to completion with rc=0
**And** the `Ensure TF state S3 bucket exists` step is **skipped** (visible in `act` log as `[skipped]` or equivalent — the `if:` condition excludes the MinIO path)
**And** the `Terraform Init` step (now `uses: ./.github/actions/init-terraform`) emits the canonical `Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!` lines
**And** the `Terraform Plan` step produces a plan against the MinIO-backed state (output to `tfplan` artifact in `${{ env.TERRAFORM_DIR }}`)
**And** the `Terraform Apply` step applies cleanly OR (if the operator's `KONNECT_TOKEN` is the `dummy` sentinel for offline verification) the apply is allowed to no-op via the existing `fetch_team` empty-data guard (see deferred-work.md § Story 1.6 verification, item 2)
**And** no `AWS_*` environment variables are required for the run to succeed (verifiable: `env | grep '^AWS_'` before invocation shows none, and the workflow does not pass any `aws-actions/configure-aws-credentials@v4` outputs into the rewired init step)
**And** no `KONNECT_TOKEN`, `VAULT_TOKEN`, or `act.secrets` value appears verbatim in the captured `act` log (verify with `grep -F "<known-secret-value>" act.log` returning no matches — NFR4 enforcement; reuse the secret-value list operators already use in their `act` test passes)

> **AC6 — Alternative (lower-effort) verification path:** If `act` rejects the rewired workflow for the same `expressions are not allowed here` reason that Story 2.2 hit on its inputs.description lines, the dev may fall back to an inlined-body shell-loop equivalent (the rewired init step expanded as `terraform init -reconfigure -input=false -upgrade -backend-config=config.minio.tfbackend` in `${TERRAFORM_DIR}`) — exactly the shape Story 2.2 used as its AC3 fallback. Document in Completion Notes which path was used and why.

### AC7 — AWS S3 forward-compat verification (no AWS credentials required)

**Given** the local docker-compose MinIO is reachable (`curl http://localhost:9000` returns a `403` or HTML response)
**And** no `AWS_*` credentials are configured in the dev environment
**When** I run, in **both** Terraform trees:
```bash
cd terraform/konnect-teams  # then repeat in .github/actions/provision-konnect-resources/terraform
rm -rf .terraform .terraform.lock.hcl
AWS_ACCESS_KEY_ID=minio-root-user \
  AWS_SECRET_ACCESS_KEY=minio-root-password \
  AWS_REGION=eu-central-1 \
  AWS_ENDPOINT_URL_S3=http://localhost:9000 \
  terraform init -reconfigure -input=false -upgrade \
    -backend-config=config.s3.tfbackend \
    -backend-config="bucket=tfstate"  # override for outer tree only; inner uses its dynamic per-team override pattern
```
**Then** for the **outer tree** (`terraform/konnect-teams`), `terraform init` succeeds with rc=0 against the existing `tfstate` MinIO bucket using the AWS S3 backend code path (verifying that the baked AWS values in `config.s3.tfbackend` from AC2 are parseable and the backend connects)
**And** for the **inner tree** (`.github/actions/provision-konnect-resources/terraform`), `terraform init` succeeds with rc=0 when invoked with the same AWS env vars plus the dynamic `-backend-config="bucket=kw.konnect.team.resources.flight-operations"` override (mirroring what the rewired action will pass via `backend-config-overrides`) — this requires pre-creating the per-team bucket on MinIO via `mc mb local/kw.konnect.team.resources.flight-operations` or equivalent; if the bucket is not pre-created, expect the canonical "Failed to get existing workspaces: bucket does not exist" error, which is a **valid AC7 pass** (it confirms the AWS S3 backend code path is reached and the rewire is correct; bucket bootstrap is Story 2.4 territory)
**And** no deprecation warnings appear in either init's stdout/stderr (`grep -i 'deprecat' init.log` returns no matches)

> **AC7 rationale:** This AC verifies the rewire does not break the AWS S3 code path **without** requiring real AWS credentials. It mirrors the proven Story 2.1 AC4 / Story 2.2 AC4 pattern of using MinIO as a fake AWS endpoint via `AWS_ENDPOINT_URL_S3`. Full end-to-end against real AWS S3 belongs to the operator's pre-merge smoke test or Epic 2.6's verification.

### AC8 — Sprint status, story status, and `git status` boundary discipline

**Given** the rewire is complete and AC1-AC7 have passed
**When** I inspect `git status --short`
**Then** the modified-file set is exactly:
```
M  .github/actions/init-terraform/action.yml         (AC1)
M  .github/actions/init-terraform/README.md          (AC1)
M  .github/actions/provision-konnect-resources/action.yaml  (AC4)
M  .github/workflows/developer-portal.yaml           (AC5)
M  .github/workflows/onboard-konnect-teams.yaml      (AC3)
M  terraform/konnect-teams/config.s3.tfbackend       (AC2)
M  _bmad-output/implementation-artifacts/sprint-status.yaml  (this AC)
M  _bmad-output/implementation-artifacts/2-3-rewire-platform-workflows-to-use-init-terraform-and-tf-backend-config.md  (this story file)
```
And **no other files are touched** — in particular: both `config.minio.tfbackend` files (Story 2.1), both `migrations/` directories (Stories 1.4/1.5), `scripts/create-s3-bucket.sh` (Story 2.4 territory), the inner tree's `config.s3.tfbackend` (per AC2 carve-out), and every other workflow file (`deploy-dp.yaml`, `test-sync-api-configuration.yaml`) are byte-identical pre and post (verifiable via `shasum -a 256` against pre-write digests captured in Subtask 1.x).
**And** no transient artifacts (`.terraform/`, `.terraform.lock.hcl`, `.tfplan`, `*.bak`, `*~`, `/tmp/*` paths) leak into `git status`
**And** [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml) is updated:
  - `development_status.2-3-rewire-platform-workflows-to-use-init-terraform-and-tf-backend-config` flips `ready-for-dev → in-progress → review` (review on completion of code-review; the dev workflow flips to `review`)
  - `last_updated` (line 2 comment **and** line 38 YAML key) bumped to the implementation date, kept hand-in-sync per the convention Story 2.1/2.2 established
  - `epic-2` status remains `in-progress` (untouched)
**And** this story file's `Status:` field at line 3 mirrors the same transition (`ready-for-dev → in-progress → review`)
**And** if any new issues surface that are out-of-scope for Story 2.3 (e.g., the `developer-portal.yaml` `AWS_S3_BUCKET` mismatch with inner-action per-team bucket; the inner-tree MinIO per-team bucket bootstrap), they are appended to [`deferred-work.md`](_bmad-output/implementation-artifacts/deferred-work.md) under a new `## Deferred from: Story 2.3 implementation (YYYY-MM-DD)` section with file:line citations

## Tasks / Subtasks

- [x] Task 1 (Pre-flight — capture state) (AC: 1, 2, 3, 4, 5, 8)
  - [x] 1.1 Verify [`.github/actions/init-terraform/action.yml`](.github/actions/init-terraform/action.yml) and `README.md` exist (Story 2.2). If missing, **HALT** — Story 2.3 cannot proceed.
  - [x] 1.2 Confirm docker-compose stack is up: `docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'minio|vault'`. If not, `docker compose up -d minio minio-create-bucket vault` and re-check.
  - [x] 1.3 Curl-probe `tfstate` bucket: `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate`. Expect `200` or `403` (bucket exists; `200` for anon-readable, `403` for anon-blocked).
  - [x] 1.4 Confirm `act` is available: `act --version`.
  - [x] 1.5 Confirm no `AWS_*` env vars are exported: `env | grep '^AWS_' && echo "WARNING: AWS env vars present" || echo "OK: clean env"`.
  - [x] 1.6 Capture pre-write sha256 digests for byte-equality-must-not-change inventory (Story 2.1's `config.minio.tfbackend` files + every workflow not being modified):
    ```bash
    shasum -a 256 \
      terraform/konnect-teams/config.minio.tfbackend \
      .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend \
      .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend \
      .github/workflows/deploy-dp.yaml \
      .github/workflows/test-sync-api-configuration.yaml \
      scripts/create-s3-bucket.sh \
      .github/actions/init-terraform/action.yml \
      .github/actions/init-terraform/README.md
    ```
    Record digests in Debug Log References (AC8 boundary discipline).

- [x] Task 2 (AC1) — Extend `init-terraform` action with `backend-config-overrides` input
  - [x] 2.1 Edit [`.github/actions/init-terraform/action.yml`](.github/actions/init-terraform/action.yml):
    - Add `backend-config-overrides` to `inputs:` block after `backend-config-path`. Use `required: false`, `default: ''`. Description: "Multiline string of `key=value` pairs (one per line). Each non-blank line is appended as an additional `-backend-config="<line>"` flag to the `terraform init` invocation. Use for dynamic backend values (per-team bucket, dynamic key, per-environment region) that cannot be baked into the file referenced by `backend-config-path`. Empty by default."
    - Update the `Terraform Init` step body. The exact target shape:
      ```yaml
      - name: Terraform Init
        shell: bash
        working-directory: ${{ inputs.terraform-dir }}
        run: |
          set -euo pipefail
          cmd=(terraform init -reconfigure -input=false -upgrade -backend-config="${{ inputs.backend-config-path }}")
          while IFS= read -r override; do
            [[ -z "$override" ]] && continue
            cmd+=(-backend-config="$override")
          done <<< "${{ inputs.backend-config-overrides }}"
          "${cmd[@]}"
      ```
    - **Critical-don't-miss:** Preserve `set -euo pipefail` (project-context Bash rule). Preserve `working-directory:`. Preserve the `-reconfigure -input=false -upgrade -backend-config=<path>` literal verbatim — the additional flags are appended only via the array build, never interleaved.
  - [x] 2.2 Validate post-write:
    ```bash
    yq eval . .github/actions/init-terraform/action.yml > /dev/null && echo "OK"
    yq eval '.inputs | keys' .github/actions/init-terraform/action.yml
    # expect: [terraform-dir, backend-config-path, backend-config-overrides]
    yq eval '.inputs."backend-config-overrides".required' .github/actions/init-terraform/action.yml  # expect: false
    yq eval '.inputs."backend-config-overrides".default' .github/actions/init-terraform/action.yml   # expect: '' (empty string)
    ```
  - [x] 2.3 Edit [`.github/actions/init-terraform/README.md`](.github/actions/init-terraform/README.md):
    - In `## Inputs` table, add a third row for `backend-config-overrides` (description, `no`, `''`).
    - In `## Example Usage`, update the AWS block to demonstrate overrides:
      ```yaml
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: latest
      - uses: ./.github/actions/init-terraform
        with:
          terraform-dir: ${{ github.action_path }}/terraform
          backend-config-path: config.s3.tfbackend
          backend-config-overrides: |
            bucket=kw.konnect.team.resources.flight-operations
            region=eu-central-1
      ```
    - Add a `## Failure Modes` entry: "**Malformed `backend-config-overrides` line** — a line without `=` is passed through unchanged; Terraform surfaces `Invalid -backend-config option` and exits non-zero. Resolution: ensure each non-blank line is `key=value`."
  - [x] 2.4 Verify P4 H2 section structure is preserved:
    ```bash
    grep -E '^## ' .github/actions/init-terraform/README.md
    # expect exactly: Overview, Inputs, Outputs, Side Effects, Example Usage, Failure Modes
    ```
  - [x] 2.5 README ↔ `action.yml` parity check (manual; pre-empts Story 4.3):
    ```bash
    for k in $(yq eval '.inputs | keys | .[]' .github/actions/init-terraform/action.yml); do
      grep -qE "^\| \`$k\`" .github/actions/init-terraform/README.md \
        && echo "OK: input $k in README" \
        || echo "FAIL: input $k missing from README"
    done
    ```

- [x] Task 3 (AC2) — Bake outer-tree static AWS values into `config.s3.tfbackend`
  - [x] 3.1 Edit [`terraform/konnect-teams/config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend):
    - Change `bucket = "tfstate"` → `bucket = "kw.konnect.teams"`.
    - Change `region = "main"` → `region = "eu-central-1"`.
    - Keep `key = "konnect.tfstate"`, `use_path_style = "true"`, `encrypt = "false"`, and the four `skip_*` keys unchanged.
    - Add a top-of-file comment block matching the style of `config.minio.tfbackend`:
      ```hcl
      # AWS-S3 backend config: routes the s3 backend at the canonical AWS-hosted state
      # bucket "kw.konnect.teams" in eu-central-1. Pairs with config.minio.tfbackend (local
      # docker-compose MinIO; default). Select at init time:
      #
      #   terraform init -reconfigure -backend-config=config.s3.tfbackend
      #
      # See _bmad-output/planning-artifacts/architecture.md § D1, P1 for the abstraction.
      ```
  - [x] 3.2 Verify the file's HCL is parseable: `terraform init -backend=false -reconfigure -backend-config=config.s3.tfbackend` from `terraform/konnect-teams/` parses the file (returns rc=0 on parse stage; will fail later if AWS creds missing — but parse stage success is the gate here).
  - [x] 3.3 **Do NOT touch** [`.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend) — inner tree's bucket is per-team and must remain caller-overridden.

- [x] Task 4 (AC3) — Rewire `onboard-konnect-teams.yaml`
  - [x] 4.1 Edit [`.github/workflows/onboard-konnect-teams.yaml`](.github/workflows/onboard-konnect-teams.yaml):
    - In the job-level `env:` block (currently lines 18-30):
      - **Add** `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` (place near the top of the env block, just after the `KONNECT_*` group, with a one-line comment "Backend selection — defaults to MinIO for local act runs; set vars.TF_BACKEND_CONFIG=config.s3.tfbackend for AWS").
      - **Keep** the `AWS_S3_BUCKET: "kw.konnect.teams"` entry — it is still consumed by the gated `Ensure TF state S3 bucket exists` step. Annotate with a one-line comment: "Transitional — consumed only by the gated bucket-creation step below; Story 2.4 (create-state-bucket.sh) will collapse this duplication with config.s3.tfbackend."
    - On the `Ensure TF state S3 bucket exists` step (currently lines 110-114), **add** `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'`. The `./create-s3-bucket.sh ${{ env.AWS_S3_BUCKET }}` invocation is **left unchanged** (Story 2.4 will sweep the script rename).
    - **Replace** the entire `Terraform Init` step block (currently lines 116-124) with:
      ```yaml
      - name: Terraform Init
        uses: ./.github/actions/init-terraform
        with:
          terraform-dir: ${{ env.TERRAFORM_DIR }}
          backend-config-path: ${{ env.TF_BACKEND_CONFIG }}
      ```
      Note: no `shell:`, no `run:`, no `working-directory:` — those are owned by the action body. No `backend-config-overrides` is passed (outer workflow has no dynamic values).
  - [x] 4.2 Validate post-write:
    ```bash
    yq eval . .github/workflows/onboard-konnect-teams.yaml > /dev/null && echo "OK"
    # No inline terraform init survives:
    grep -n 'terraform init' .github/workflows/onboard-konnect-teams.yaml | grep -v 'init-terraform' && echo "FAIL: inline terraform init remains" || echo "OK: only init-terraform action reference"
    # Exactly one init-terraform usage:
    grep -c 'uses: ./.github/actions/init-terraform' .github/workflows/onboard-konnect-teams.yaml
    # expect: 1
    # TF_BACKEND_CONFIG present:
    yq eval '.jobs."onboard-konnect-teams".env."TF_BACKEND_CONFIG"' .github/workflows/onboard-konnect-teams.yaml
    # AWS_S3_BUCKET still present (transitional):
    yq eval '.jobs."onboard-konnect-teams".env."AWS_S3_BUCKET"' .github/workflows/onboard-konnect-teams.yaml
    # expect: kw.konnect.teams
    ```
  - [x] 4.3 Verify the gated step's `if:` reads correctly:
    ```bash
    yq eval '.jobs."onboard-konnect-teams".steps[] | select(.name == "Ensure TF state S3 bucket exists") | .if' .github/workflows/onboard-konnect-teams.yaml
    # expect: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'
    ```

- [x] Task 5 (AC4) — Rewire `provision-konnect-resources/action.yaml`
  - [x] 5.1 Edit [`.github/actions/provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml):
    - **Replace** the entire `Terraform Init` step block (currently lines 109-116) with:
      ```yaml
      - name: Terraform Init
        uses: ./.github/actions/init-terraform
        with:
          terraform-dir: ${{ github.action_path }}/terraform
          backend-config-path: ${{ env.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}
          backend-config-overrides: |
            bucket=kw.konnect.team.resources.${{ inputs.konnect-team-name }}
            region=${{ inputs.aws-region }}
      ```
    - **Critical-don't-miss:** The `backend-config-overrides` value is a YAML literal-block scalar (`|`). Two lines, no leading/trailing whitespace beyond the YAML indentation. The newline between them is preserved through `act` and GitHub Actions.
    - **Critical-don't-miss:** `${{ env.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` uses the GitHub-expression `||` operator, which returns the right-hand side when the left is falsy (unset / empty). This makes the action standalone-usable: if a caller does not set `TF_BACKEND_CONFIG`, MinIO is the default.
  - [x] 5.2 Validate post-write:
    ```bash
    yq eval . .github/actions/provision-konnect-resources/action.yaml > /dev/null && echo "OK"
    grep -n 'terraform init' .github/actions/provision-konnect-resources/action.yaml | grep -v 'init-terraform' && echo "FAIL" || echo "OK"
    grep -c 'uses: ./.github/actions/init-terraform' .github/actions/provision-konnect-resources/action.yaml
    # expect: 1
    # The action's inputs block is byte-identical pre and post (no contract change):
    yq eval '.inputs | keys' .github/actions/provision-konnect-resources/action.yaml
    ```
  - [x] 5.3 Verify the `Terraform Plan` and `Terraform Apply` / `destroy` steps (currently lines 118-143) are byte-identical pre and post. `diff` against pre-write copy.

- [x] Task 6 (AC5) — Rewire `developer-portal.yaml`
  - [x] 6.1 Edit [`.github/workflows/developer-portal.yaml`](.github/workflows/developer-portal.yaml):
    - In the job-level `env:` block (currently lines 26-38), **add** `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` (place near the top, just after the `KONNECT_*` group).
    - On the `Ensure TF state S3 bucket exists` step (currently lines 54-58), **add** `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'`. Leave the existing `./create-s3-bucket.sh ${{ env.AWS_S3_BUCKET }}` invocation UNCHANGED (Story 2.4 will sweep the script rename).
    - **Do NOT remove** the `AWS_S3_BUCKET: "kw.konnect.dev-portal-terraform-state"` env entry — still consumed by the (now gated) `create-s3-bucket.sh` step.
    - The `Provision Konnect Developer Portal resources` step (lines 60-77) is **untouched**.
  - [x] 6.2 Validate post-write:
    ```bash
    yq eval . .github/workflows/developer-portal.yaml > /dev/null && echo "OK"
    yq eval '.jobs."developer-portal".env."TF_BACKEND_CONFIG"' .github/workflows/developer-portal.yaml
    yq eval '.jobs."developer-portal".steps[] | select(.name == "Ensure TF state S3 bucket exists") | .if' .github/workflows/developer-portal.yaml
    ```

- [x] Task 7 (AC6) — End-to-end MinIO verification via `act`
  - [x] 7.1 Confirm prereqs (re-run Task 1.2-1.5).
  - [x] 7.2 Confirm `act.secrets` exists with a valid `KONNECT_TOKEN` (or `KONNECT_PAT` per deferred-work.md § Story 1.6 item 3 — both names are in flight; use whichever the operator's local environment has).
  - [x] 7.3 Confirm `teams/flight-operations.yaml` is present and validates: `yq eval '.name, .entitlements' teams/flight-operations.yaml`.
  - [x] 7.4 Run:
    ```bash
    act -W .github/workflows/onboard-konnect-teams.yaml \
        --network host \
        --secret-file act.secrets \
        workflow_dispatch \
        2>&1 | tee /tmp/act-2-3-onboard.log
    ```
  - [x] 7.5 Assert outcomes from the captured log:
    - Final exit code 0 (or 1 only if attributable to the documented Vault provider gap from deferred-work.md § Story 1.6 item 1 — see Critical-don't-miss below).
    - `Ensure TF state S3 bucket exists` step status = skipped.
    - `Terraform Init` step status = success; log contains `Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!`.
    - `Terraform Plan` step status = success; log contains `Plan: N to add, M to change, K to destroy` for some N/M/K.
    - `Terraform Apply` step: success on apply OR documented Vault-provider-gap failure (deferred-work.md § Story 1.6 item 1). If Vault gap fires, document this in Completion Notes as an "intent-satisfied" pass per Story 2.1 precedent.
    - No `KONNECT_TOKEN` or `VAULT_TOKEN` value appears verbatim in the log: `grep -F "$KONNECT_TOKEN" /tmp/act-2-3-onboard.log` returns no matches (NFR4).
  - [x] 7.6 If `act` rejects the workflow at parse time for `expressions are not allowed here` (Story 2.2 hit this on inputs.description), fall back to the AC6 inlined-body shell-loop equivalent and document the path taken in Completion Notes.

- [x] Task 8 (AC7) — AWS S3 forward-compat verification (no AWS creds)
  - [x] 8.1 **Outer tree** verification:
    ```bash
    cd terraform/konnect-teams
    rm -rf .terraform .terraform.lock.hcl
    AWS_ACCESS_KEY_ID=minio-root-user \
      AWS_SECRET_ACCESS_KEY=minio-root-password \
      AWS_REGION=eu-central-1 \
      AWS_ENDPOINT_URL_S3=http://localhost:9000 \
      terraform init -reconfigure -input=false -upgrade \
        -backend-config=config.s3.tfbackend \
        -backend-config="bucket=tfstate" \
        2>&1 | tee /tmp/init-outer-s3.log
    # NOTE: bucket override to "tfstate" is for verification only — bypasses the
    # need to pre-create "kw.konnect.teams" on MinIO. Confirms config.s3.tfbackend
    # parses and the AWS backend code path is reachable.
    ```
    Assert rc=0; `Successfully configured the backend "s3"!` present; no `deprecat*` in stdout/stderr.
  - [x] 8.2 **Inner tree** verification:
    ```bash
    cd .github/actions/provision-konnect-resources/terraform
    rm -rf .terraform .terraform.lock.hcl
    AWS_ACCESS_KEY_ID=minio-root-user \
      AWS_SECRET_ACCESS_KEY=minio-root-password \
      AWS_REGION=eu-central-1 \
      AWS_ENDPOINT_URL_S3=http://localhost:9000 \
      terraform init -reconfigure -input=false -upgrade \
        -backend-config=config.s3.tfbackend \
        -backend-config="bucket=tfstate" \
        -backend-config="region=eu-central-1" \
        2>&1 | tee /tmp/init-inner-s3.log
    # bucket override to "tfstate" mirrors what backend-config-overrides will pass
    # via the rewired action; "tfstate" is the only MinIO bucket pre-created.
    ```
    Assert rc=0; `Successfully configured the backend "s3"!` present.
  - [x] 8.3 Clean up: `rm -rf terraform/konnect-teams/.terraform terraform/konnect-teams/.terraform.lock.hcl .github/actions/provision-konnect-resources/terraform/.terraform .github/actions/provision-konnect-resources/terraform/.terraform.lock.hcl`. Also: `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_ENDPOINT_URL_S3` to leave the dev environment as found.

- [x] Task 9 (AC8) — Sprint status, story status, deferred-work boundary discipline
  - [x] 9.1 `git status --short`: verify exactly the 8 modified files listed in AC8 are present, no others.
  - [x] 9.2 `shasum -a 256` re-check the byte-equality-must-not-change inventory captured in Task 1.6. All must match.
  - [x] 9.3 Update [`sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml):
    - Bump `last_updated` (line 2 comment + line 38 YAML key) to today's date, kept hand-in-sync per Story 2.1/2.2 convention.
    - Flip `2-3-rewire-platform-workflows-to-use-init-terraform-and-tf-backend-config` from `ready-for-dev` → `in-progress` → `review` (the dev-story workflow flips to `review` on completion).
  - [x] 9.4 This file's `Status:` (line 3): flip `ready-for-dev` → `in-progress` → `review` correspondingly.
  - [x] 9.5 If new out-of-scope concerns surfaced during implementation (e.g., `developer-portal.yaml` AWS_S3_BUCKET mismatch with inner-action bucket; MinIO per-team bucket bootstrap for inner-action multi-team), append them to [`deferred-work.md`](_bmad-output/implementation-artifacts/deferred-work.md) under a new `## Deferred from: Story 2.3 implementation (YYYY-MM-DD)` section with `(SEV)` rating, file:line citations, and resolution prescriptions.
  - [x] 9.6 Populate the **Dev Agent Record** sections below (Agent Model Used, Debug Log References, Completion Notes List, File List).

### Review Findings

_Code review performed 2026-05-12 — three parallel layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor). 2 decision-needed (both resolved no-patch), 0 unconditional patches, 4 deferred, 12 dismissed._

**Decision-needed (resolved by operator):**

- [x] [Review][Decision] **AWS state-key relocation: `tfstate` → `konnect.tfstate`** — Pre-diff, `onboard-konnect-teams.yaml` inlined `-backend-config="key=tfstate"` which overrode the file's `key = "konnect.tfstate"`. Post-diff, no override is passed and the file value wins. Effective state path moves from `s3://kw.konnect.teams/tfstate` to `s3://kw.konnect.teams/konnect.tfstate`. **Operator decision (2026-05-12, Jordi):** AWS path was never run with real values — the pre-diff `bucket = "tfstate"` and `region = "main"` were placeholder sentinels; no real AWS state exists at the old key. `konnect.tfstate` is the new canonical key and no migration is required. [terraform/konnect-teams/config.s3.tfbackend:9](terraform/konnect-teams/config.s3.tfbackend#L9).

- [x] [Review][Decision] **`encrypt = "false"` retained on the now-real AWS state bucket** — AC2 mandated the flag be left unchanged; the flag was appropriate for MinIO (the previous effective destination) but the now-baked AWS values change the situation. **Operator decision (2026-05-12, Jordi):** bucket-level SSE is already enforced on `kw.konnect.teams`, so the per-state `encrypt = "false"` is moot. Spec letter wins; no patch. [terraform/konnect-teams/config.s3.tfbackend:12](terraform/konnect-teams/config.s3.tfbackend#L12).

**Deferred (real but out-of-scope or low likelihood):**

- [x] [Review][Defer] **CRLF stripping missing in `init-terraform` override loop** [.github/actions/init-terraform/action.yml:25-29](.github/actions/init-terraform/action.yml#L25-L29) — `IFS= read -r` does not strip `\r`; a CRLF-saved override block would append `-backend-config="region=eu-central-1\r"` and fail opaquely. Pre-conditions (Windows-edited YAML) are unlikely in this team's flow. Defensive one-liner (`override="${override%$'\r'}"`) would deviate from AC1's mandated literal body — defer to a future hardening pass.

- [x] [Review][Defer] **Empty-string `TF_BACKEND_CONFIG` would split-brain `onboard-konnect-teams.yaml`** [.github/workflows/onboard-konnect-teams.yaml:125](.github/workflows/onboard-konnect-teams.yaml#L125) — `backend-config-path: ${{ env.TF_BACKEND_CONFIG }}` has no `|| 'config.minio.tfbackend'` fallback (the workflow-env line 25 does, so this only fires if `vars.TF_BACKEND_CONFIG` is explicitly set to `""`). In that case, the gate at line 115 fires (`"" != 'config.minio.tfbackend'`) → AWS bucket created → init falls back to MinIO via the action default. Defensive symmetry: mirror the `||` in the `with:` block. Low likelihood (explicit empty repo-var), defer.

- [x] [Review][Defer] **Gate uses naive string-equality, not path-normalised** [.github/workflows/onboard-konnect-teams.yaml:115](.github/workflows/onboard-konnect-teams.yaml#L115), [.github/workflows/developer-portal.yaml:58](.github/workflows/developer-portal.yaml#L58) — `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'` returns true for `./config.minio.tfbackend`, `'config.minio.tfbackend '` (trailing space), or uppercase variants. Operator typo in repo variable spuriously runs `create-s3-bucket.sh` against AWS. Story 4.4's `lint-no-bypass.yaml` is the natural place to add a magic-string lint; defer.

- [x] [Review][Defer] **`konnect-team-name` substitution into bucket name lacks shell-meta sanitization** [.github/actions/provision-konnect-resources/action.yaml:115](.github/actions/provision-konnect-resources/action.yaml#L115) — `bucket=kw.konnect.team.resources.${{ inputs.konnect-team-name }}` is fine for validator-enforced names (lowercase alphanumeric + hyphens per the YAML validator), but the inner action does not re-validate its own input. Today's threat model (operator-controlled callers, validator runs before the action) covers this; defer to Story 4.x hardening that env-indirects `${{ inputs.* }}` substitutions repo-wide.

**Dismissed (verified, intentional, or already-deferred):**

- ✓ Template-injection on `${{ inputs.backend-config-overrides }}` / `${{ inputs.backend-config-path }}` — already tracked in [deferred-work.md "Deferred from: Story 2.3 implementation"](_bmad-output/implementation-artifacts/deferred-work.md) (bundled with the existing Story 2.2 entry).
- ✓ Inner-action defaults `backend-config-path` to MinIO while passing AWS-shaped overrides — already tracked in [deferred-work.md "MinIO multi-team gap"](_bmad-output/implementation-artifacts/deferred-work.md) and "Critical-don't-miss: MinIO single-bucket model vs. AWS per-team-bucket model" (Dev Notes).
- ✓ `region=…` override leaks into MinIO path of inner action — same as above; folded into the MinIO multi-team deferred entry.
- ✓ `-reconfigure` discards backend state on long-lived runners — intentional and safer than implicit `-migrate-state`; preserves the canonical action body Story 2.2 mandated.
- ✓ `use_path_style = "true"` against real AWS S3 — required, not optional: the bucket name `kw.konnect.teams` contains dots, which breaks virtual-hosted-style TLS SNI. Path-style is correct here.
- ✓ Hardcoded `region = "eu-central-1"` replacing `${{ env.AWS_REGION }}` — aligns with project-context's "AWS provider region hardcoded to eu-central-1" rule; intentional.
- ✓ `set -u` + `<<< ""` empty-default loop behavior — verified harmless: `<<<` appends a trailing newline; empty input yields one iteration with empty `$override`, the `-z` guard `continue`s, second `read` returns non-zero, the `while` condition consumes the non-zero (loop conditions are exempt from `set -e`).
- ✓ `developer-portal.yaml` does not directly call `init-terraform` — by design (AC5): the inner `provision-konnect-resources` action inherits the job-level `TF_BACKEND_CONFIG` env and does its own init.
- ✓ Story file shows as `??` rather than `M` in `git status` — cosmetic: the file is a new untracked artifact created during implementation; spec intent (file present, status `review`) is met.
- ✓ Sprint-status transition started at `backlog` not `ready-for-dev` — spec premise inaccuracy, not implementation defect; terminal state `review` is correct.
- ✓ Magic-string `'config.minio.tfbackend'` duplicated in two workflow gates and the composite default — Story 4.x territory; not introduced by this story.
- ✓ `read` exit status under `set -e` for no-trailing-newline input — `<<<` always appends a newline; not reachable.

## Dev Notes

### Why this story exists

Story 2.2 introduced the shared `init-terraform` composite action; today it sits unused by CI. Two inline `terraform init` call sites remain — [`onboard-konnect-teams.yaml:116-124`](.github/workflows/onboard-konnect-teams.yaml#L116-L124) and [`provision-konnect-resources/action.yaml:109-116`](.github/actions/provision-konnect-resources/action.yaml#L109-L116) — and the lack of a `TF_BACKEND_CONFIG` env-driven selector means `act`-driven local runs cannot reach the MinIO backend without hand-editing the workflow file. Story 2.3 closes the loop: every Terraform-touching workflow and action uses one canonical init path, and backend selection lives at one configuration boundary (`TF_BACKEND_CONFIG` env var → `init-terraform` action input → `.tfbackend` file).

This is also the first real exercise of the `init-terraform` action's contract; if AC1's `backend-config-overrides` addition is wrong-shaped, the next four stories (2.4-2.6, and 3.x's deploy-dp rewires that may need init too) inherit the wrong shape.

### What this story does NOT do

- It does **not** rename `scripts/create-s3-bucket.sh` to `scripts/create-state-bucket.sh`. The epic AC names this as "(delivered in Story 2.4)". Story 2.3 gates the existing `create-s3-bucket.sh` invocations behind `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'` — Story 2.4 will sweep the rename and add the MinIO-mode branch. See [`epics.md:436-459`](_bmad-output/planning-artifacts/epics.md#L436-L459).
- It does **not** touch [`.github/workflows/test-sync-api-configuration.yaml`](.github/workflows/test-sync-api-configuration.yaml). That workflow calls the `sync-api-configuration` composite action (decK-based, not Terraform-based) and contains no `terraform init` invocation. The epic AC at [`epics.md:423`](_bmad-output/planning-artifacts/epics.md#L423) names it, but the actual file proves it does no Terraform work today — the spec's enumeration is forward-looking. Verifiable via `grep -c terraform .github/workflows/test-sync-api-configuration.yaml` returning `0`.
- It does **not** touch [`.github/workflows/deploy-dp.yaml`](.github/workflows/deploy-dp.yaml). That workflow does no Terraform work (it deploys a Helm chart). Story 3.x will revisit it for the `kubeconfig-path` / `kubeconfig-content` input wiring per architecture D2.
- It does **not** address the inner-action MinIO per-team bucket bootstrap question. With `backend-config-overrides` set to `bucket=kw.konnect.team.resources.<team-name>`, an `act`-driven `developer-portal.yaml` run against MinIO would attempt to write state to a per-team bucket that does not exist on the local MinIO. AC6 only verifies `onboard-konnect-teams.yaml` (which does **not** use per-team buckets). End-to-end verification of `developer-portal.yaml` against local MinIO multi-team is Epic 2.6 territory.
- It does **not** fix the pre-existing mismatch in [`developer-portal.yaml:38,77`](.github/workflows/developer-portal.yaml#L38) between the `AWS_S3_BUCKET: "kw.konnect.dev-portal-terraform-state"` env (consumed by `create-s3-bucket.sh`) and the inner-action's per-team bucket pattern (`kw.konnect.team.resources.portal-admin`). Two different buckets get touched by the same workflow run for unrelated reasons. Pre-dates Story 2.3; surface in deferred-work.md if not already.
- It does **not** introduce the `lint-action-contracts.yaml` CI workflow (Story 4.3) or `lint-no-bypass.yaml` (Story 4.4). AC1's README ↔ `action.yml` parity is a manual check; Story 4.3 will mechanize it.
- It does **not** revisit the open design question logged by Story 2.2 about `backend-config-overrides` shape. **Decision recorded here:** option (a) from Story 2.2's Dev Notes (additive multiline input to init-terraform) is the resolution. Options (b) (caller-side second init step) and (c) (hardcode per-team bucket in `.tfbackend`) were rejected as anti-P1 (sed/envsubst templating) or as requiring caller-side branching that defeats the abstraction.

### Critical-don't-miss: `TF_BACKEND_CONFIG` env-var inheritance from workflow → composite action

GitHub Actions composite actions inherit job-level `env:` declarations from the calling workflow automatically — no explicit pass-through is required. This is **why** [`provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml) can reference `${{ env.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` at the `backend-config-path` input without any caller-side `with:` plumbing. Verify:

> Reference: GitHub Actions docs — "Environment variables defined in the env key for individual steps will override variables defined at the workflow or job level for that step only." Composite-action steps see the calling job's env.

If a future caller (API team workflow in a sister repo) consumes `provision-konnect-resources` without setting `TF_BACKEND_CONFIG`, the action defaults to `config.minio.tfbackend` — wrong choice for a cloud-CI context. **Document this as a contract requirement in the action's README during Story 4.2** (out of scope for 2.3 to write that README; just surface as a Completion Notes hand-off item).

### Critical-don't-miss: bash array-build pattern for variadic `-backend-config` flags

The action body uses Bash's array-append pattern (`cmd=(terraform init …); cmd+=(-backend-config="$override"); "${cmd[@]}"`) instead of string concatenation, because:

1. **Quoting safety:** A `key=val with spaces` override expands correctly through `${cmd[@]}` ("$@"-style expansion). String concatenation breaks on whitespace.
2. **No backslash continuations:** The old inline call site used `\` line-continuations that break under `set -e` if any pre-line errors. Array form is cleaner.
3. **Empty-line handling:** The `[[ -z "$override" ]] && continue` guard skips blank lines from the YAML literal block (a trailing newline in the YAML produces one extra empty line on `read`).

**Do NOT** rewrite to `terraform init … $extra_flags` (unquoted) — that re-introduces word-splitting on overrides like `key="value with spaces"`. The array form is load-bearing.

### Critical-don't-miss: `${{ inputs.backend-config-overrides }}` template interpolation in heredoc

The action body uses `<<< "${{ inputs.backend-config-overrides }}"` — a here-string fed from a GitHub-expression substitution. Two non-obvious behaviors:

1. **Newlines are preserved through `${{ ... }}` interpolation.** A YAML literal-block scalar (`|`) value gets passed verbatim with `\n` between lines. The Bash `while read` loop correctly iterates one line per override.
2. **The template-injection caveat from Story 2.2 applies here too.** Both `inputs.backend-config-path` (existing) and `inputs.backend-config-overrides` (new) substitute literal text into a `run:` body. An adversarial caller could inject `"$(rm -rf /)"` as override content and execute it. Today's threat model — operator-controlled callers only — accepts this. Story 4.x hardening would env-indirect both inputs (`env: BCO: ${{ inputs.backend-config-overrides }}` + `<<< "$BCO"`). Surface in deferred-work.md under the existing Story 2.2 review entry; do not harden in Story 2.3 (out of scope, would diverge from AC1's literal body).

### Critical-don't-miss: MinIO single-bucket model vs. AWS per-team-bucket model

The local docker-compose MinIO instance has exactly one auto-created bucket: `tfstate`. The `minio-create-bucket` companion service ([`docker-compose.yaml`](docker-compose.yaml)) creates only this one. Two consequences for Story 2.3:

1. **Outer workflow (`onboard-konnect-teams.yaml`)** under MinIO uses `bucket = "tfstate"`, `key = "konnect.tfstate"`. Single global state. ✓
2. **Inner action (`provision-konnect-resources`)** under MinIO with `backend-config-overrides: "bucket=kw.konnect.team.resources.${{ inputs.konnect-team-name }}\n..."` will **attempt** to write to a per-team bucket that does **not** exist. `terraform init` will fail with "Failed to get existing workspaces: bucket does not exist."

AC6 verifies `onboard-konnect-teams.yaml` only — the inner-action MinIO multi-team case is **out of scope** (Epic 2.6 territory). For Story 2.3, the inner action's `backend-config-overrides` is correct **for AWS**; for MinIO via `act`, it will fail unless the operator pre-creates the per-team bucket via `mc mb local/kw.konnect.team.resources.<team-name>`. **Document this limitation in deferred-work.md** under the new Story 2.3 implementation section so Story 2.6's verification path is aware.

Future fix candidates (out of scope here): (i) update `minio-create-bucket` to create a static set of per-team buckets; (ii) move the inner-action per-team partitioning from bucket-level to key-level (`key=team-resources/${name}.tfstate` with a single shared bucket — works on both backends).

### Critical-don't-miss: `${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` semantics

The `||` operator in GitHub-expressions returns the right-hand operand when the left is **falsy** (empty string, null, false, 0). For workflow-level repository variables (`vars.X`):

- If `vars.TF_BACKEND_CONFIG` is **not defined** in the repo's Variables settings, `vars.TF_BACKEND_CONFIG` evaluates to empty string → the `||` returns the default `'config.minio.tfbackend'`. ✓
- If defined as `config.s3.tfbackend`, returns that value. ✓
- If defined as an empty string explicitly (UI weirdness): returns the default. ✓

This is the correct default-fallback shape for a setting the operator may or may not configure. `act` does **not** inject GitHub-level `vars.*` automatically; `act`-driven runs therefore always pick the `'config.minio.tfbackend'` default — which is exactly what AC6 needs.

### Critical-don't-miss: P3 step-name discipline

Per architecture pattern P3 ([`architecture.md:263-271`](_bmad-output/planning-artifacts/architecture.md#L263-L271)), every "validation gate" step must use a `name:` whose leading word is `Validate`, `Lint`, or `Plan`. Story 2.3 touches three such steps without renaming them:

- `Validate config` (onboard-konnect-teams.yaml line 51) — keep verbatim.
- `Terraform Plan` (onboard-konnect-teams.yaml line 126; provision-konnect-resources/action.yaml line 118) — keep verbatim.

The new `Terraform Init` step (added via `uses:`) is **not** a validation gate and is **not** subject to P3. The existing `Terraform Init` name is preserved for git-history continuity and grep-discoverability.

Story 4.4's `lint-no-bypass.yaml` (future) keys off the P3 prefix; Story 2.3's preservation ensures forward compatibility.

### Critical-don't-miss: `act` host-network for MinIO reachability

Per Story 2.2's Dev Notes and [`.actrc.tpl`](.actrc.tpl), `act` runs the runner container in `--network host` mode so that `http://localhost:9000` (MinIO) and `http://localhost:8300` (Vault dev container) are reachable from inside the act-runner. AC6's explicit `--network host` flag is defensive: if `.actrc` is not yet generated from `.actrc.tpl` on a fresh clone, the flag provides the same effect inline. Do **not** assume `.actrc` is present.

### Critical-don't-miss: `act` and `${{ expressions }}` inside `inputs.<name>.description:`

Story 2.2's AC3 hit `act` parse-time failure `Line: 6 Column 18: expressions are not allowed here` on the `${{ ... }}` text inside the action's `inputs.*.description:` strings. Cause: `act`'s YAML parser strictness diverges from real GitHub Actions (which accepts arbitrary text in description metadata). For Story 2.3:

- The **new** `backend-config-overrides` input description should avoid `${{ ... }}` substring tokens entirely. Use plain text references like "the calling workflow's TF_BACKEND_CONFIG env var" instead of `${{ env.TF_BACKEND_CONFIG }}`.
- If AC6's `act` invocation hits the same error on a previously-introduced description string, follow Story 2.2's documented AC3 fallback (inlined-body shell equivalent).

### Previous-story intelligence (Story 2.2)

- **Action body shape (verbatim baseline):** [Story 2.2 AC1](_bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md#L40) mandates `terraform init -reconfigure -input=false -upgrade -backend-config="${{ inputs.backend-config-path }}"`. Story 2.3 preserves this exact substring inside the new array-build body — every Story 2.3 change is **additive**.
- **P4 README structure is forward-mechanically-enforced** by Story 4.3 ([`epics.md:636-660`](_bmad-output/planning-artifacts/epics.md#L636-L660)). Story 2.3's README update **must** keep the six H2 sections (`Overview`, `Inputs`, `Outputs`, `Side Effects`, `Example Usage`, `Failure Modes`) in canonical order with `_None._` as the Outputs body. Do **not** introduce a "Behavior" or "Usage" heading from the pre-P4 era — see Story 2.2 Dev Notes "Critical-don't-miss: P4 README structure is mechanically enforced (eventually)" ([line 400-406](_bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md)).
- **`Outputs` section must NOT be removed:** Story 2.2 documented that an absent `## Outputs` section fails the P4 structural diff. Story 2.3's edits never touch the `## Outputs` section — leave `_None._`.
- **Sprint-status `last_updated` hand-sync convention:** Story 2.1 review item ([deferred-work.md line 67](_bmad-output/implementation-artifacts/deferred-work.md)) flagged that line 2 (comment) and line 38 (YAML key) carry the same date and require hand-editing in sync. Story 2.2 honored this. Story 2.3 must too.
- **Deferred items from Story 2.2 that this story partially addresses:** (i) [Story 2.2 review item 1](_bmad-output/implementation-artifacts/deferred-work.md#L73) — template-injection on `${{ inputs.backend-config-path }}` substitution — **not addressed** here (Story 2.3 perpetuates the pattern faithfully for `backend-config-overrides`); (ii) Story 2.2 Dev Notes "What this story does NOT do" item 4 — open design question on dynamic overrides — **addressed** here via option (a), the new `backend-config-overrides` input.

### Git intelligence (recent commits)

- `d928a0d Update deferred work and sprint status for story 2-2` — Story 2.2 wrap-up; deferred-work.md format for Story 2.2 items established.
- `74a29fc feat: add MinIO backend configuration and update sprint status` — Story 2.1 commit; pattern for config.*.tfbackend file annotations (top-comment block matching style across paired files) established.
- `b040f51 feat: implement migration driver script and update sprint status` — Story 1.5; `set -euo pipefail` discipline reinforced for non-trivial bash steps.
- `03c282b feat(migrations): add migration script for Konnect provider upgrade from 3.1.0 to 3.15.0` — Story 1.4; conventional-commit `feat(scope): ...` style. Story 2.3's commit should follow `feat(init-terraform): plumb backend-config-overrides input and rewire platform workflows to TF_BACKEND_CONFIG` or `feat: rewire platform workflows to init-terraform action with TF_BACKEND_CONFIG selector`.
- Current branch `new-gen` (per git status) accumulates Epic-1 and Epic-2 work; commit Story 2.3 to `new-gen`, not `main`.

### Design alternatives considered (and rejected)

1. **Caller-side second `terraform init -backend-config="bucket=…"` step after the `init-terraform` action call.** Rejected — duplicates init invocations (two reconfigures per run, double the network round-trips to MinIO/S3), and leaves caller-side template-injection surface unchanged. Architecture P1 ("file-driven backend selection") is also violated by re-introducing per-caller flag plumbing.
2. **Hardcode the inner-action per-team bucket name into `config.s3.tfbackend`.** Rejected — the inner tree is invoked once per team (each API team has its own `konnect-team-name`). A single static bucket cannot represent N teams. Would require N config files or a templating pass (anti-P1).
3. **Replace bucket-level partitioning with key-level partitioning for the inner tree on both backends.** Considered — `key=team-resources/${team-name}.tfstate` in a single shared bucket works on MinIO and AWS, and eliminates the AC4 `backend-config-overrides` complexity. Rejected for Story 2.3 because it changes the inner action's AWS state layout (existing `kw.konnect.team.resources.<team>` buckets across teams) — a destructive migration. Surface as a candidate for a future Epic-2 cleanup story; record in deferred-work.md.
4. **Pass `backend-config-overrides` as an array-of-strings input.** Rejected — GitHub-Actions composite-action `inputs:` are strings only (no list type). Multiline string with newline separator is the canonical pattern.
5. **Wrap the bash array-build inside a helper script under `.github/actions/init-terraform/scripts/`.** Rejected — adds a second file to the action without complexity justification. The Bash body is 7 lines; readable inline.
6. **Add a `backend-config-overrides-file` input pointing at a multi-line file path instead.** Rejected — adds a layer of indirection without benefit, and the file would need YAML-style escaping that defeats the use case.

### File inventory (after this story)

```
.github/actions/init-terraform/action.yml                     ← MODIFIED (AC1 — new input)
.github/actions/init-terraform/README.md                      ← MODIFIED (AC1 — new input row + AWS example + new failure mode)
.github/actions/provision-konnect-resources/action.yaml       ← MODIFIED (AC4 — Terraform Init step replaced)
.github/workflows/onboard-konnect-teams.yaml                  ← MODIFIED (AC3 — TF_BACKEND_CONFIG env, gated bucket step, Init step replaced, AWS_S3_BUCKET env removed)
.github/workflows/developer-portal.yaml                       ← MODIFIED (AC5 — TF_BACKEND_CONFIG env, gated bucket step)
terraform/konnect-teams/config.s3.tfbackend                   ← MODIFIED (AC2 — static AWS values baked, top-comment added)

.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend  ← UNCHANGED (per AC2 carve-out)
terraform/konnect-teams/config.minio.tfbackend                ← UNCHANGED (Story 2.1)
.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend ← UNCHANGED (Story 2.1)
.github/workflows/test-sync-api-configuration.yaml            ← UNCHANGED (no terraform work)
.github/workflows/deploy-dp.yaml                              ← UNCHANGED (no terraform work; Story 3.x)
scripts/create-s3-bucket.sh                                   ← UNCHANGED (Story 2.4 territory)

_bmad-output/implementation-artifacts/sprint-status.yaml      ← MODIFIED (AC8 — status flips + last_updated)
_bmad-output/implementation-artifacts/2-3-rewire-platform-workflows-to-use-init-terraform-and-tf-backend-config.md ← MODIFIED (this file; AC8 — Status field + Dev Agent Record)
_bmad-output/implementation-artifacts/deferred-work.md        ← MODIFIED (only if new deferred items surface; AC8 hand-off)
```

### References

- Epic 2 narrative: [`epics.md:365-505`](_bmad-output/planning-artifacts/epics.md#L365-L505)
- Story 2.3 source: [`epics.md:414-434`](_bmad-output/planning-artifacts/epics.md#L414-L434)
- Architecture D1 (state backend abstraction): [`architecture.md:157-163`](_bmad-output/planning-artifacts/architecture.md#L157-L163)
- Architecture P1 (backend-config selection): [`architecture.md:246-251`](_bmad-output/planning-artifacts/architecture.md#L246-L251)
- Architecture P3 (validate/lint/plan step prefix): [`architecture.md:263-271`](_bmad-output/planning-artifacts/architecture.md#L263-L271)
- Architecture P4 (Action README structure): [`architecture.md:272-284`](_bmad-output/planning-artifacts/architecture.md#L272-L284)
- Architecture target tree (init-terraform location): [`architecture.md:360-363`](_bmad-output/planning-artifacts/architecture.md#L360-L363)
- Architecture anti-patterns (sed/envsubst templating, backend branching): [`architecture.md:330-334`](_bmad-output/planning-artifacts/architecture.md#L330-L334)
- Project-context Bash rules (`set -euo pipefail`, no secret echoing, OS detection): [`project-context.md:65-70`](_bmad-output/project-context.md#L65-L70)
- Project-context composite-action rules (`shell: bash`, `${{ github.action_path }}`, explicit secret passing): [`project-context.md:88-94`](_bmad-output/project-context.md#L88-L94)
- Project-context workflow rules (job-level env centralization, `vars.*` vs `secrets.*`): [`project-context.md:95-101`](_bmad-output/project-context.md#L95-L101)
- Project-context action/workflow style (step `name:`, `working-directory:`, env references): [`project-context.md:160-164`](_bmad-output/project-context.md#L160-L164)
- Project-context anti-patterns (no `continue-on-error: true`, no `|| true` on validators, `terraform plan` to file): [`project-context.md:207-217`](_bmad-output/project-context.md#L207-L217)
- Story 2.1 (config.minio.tfbackend files; pre-existing AC2 inputs): [`2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md`](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md)
- Story 2.2 (init-terraform action; pre-existing AC1 + AC2 contract): [`2-2-create-shared-init-terraform-composite-action.md`](_bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md)
- Story 2.2 open design question (resolved here via option a): [`2-2-create-shared-init-terraform-composite-action.md` Dev Notes "What this story does NOT do" item 4](_bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md#L395)
- Story 2.4 (script rename — Story 2.3 gates create-s3-bucket.sh for handoff): [`epics.md:436-459`](_bmad-output/planning-artifacts/epics.md#L436-L459)
- Story 2.6 (end-to-end on clean macOS — verifies the full chain): [`epics.md:480-505`](_bmad-output/planning-artifacts/epics.md#L480-L505)
- Story 4.2 (README parity retrofits — provision-konnect-resources/README.md will be updated to document TF_BACKEND_CONFIG contract): [`epics.md:616-634`](_bmad-output/planning-artifacts/epics.md#L616-L634)
- Story 4.3 (mechanizes README ↔ action.yml lint — accepts the new `backend-config-overrides` row): [`epics.md:636-660`](_bmad-output/planning-artifacts/epics.md#L636-L660)
- Story 4.4 (mechanizes P3 step-name + no-bypass lint): [`epics.md:662-686`](_bmad-output/planning-artifacts/epics.md#L662-L686)
- Outer-tree call site (rewired by AC3): [`.github/workflows/onboard-konnect-teams.yaml:116-124`](.github/workflows/onboard-konnect-teams.yaml#L116-L124)
- Inner-tree call site (rewired by AC4): [`.github/actions/provision-konnect-resources/action.yaml:109-116`](.github/actions/provision-konnect-resources/action.yaml#L109-L116)
- Inner-tree create-s3-bucket invocation (gated by AC5; renamed by Story 2.4): [`.github/workflows/developer-portal.yaml:54-58`](.github/workflows/developer-portal.yaml#L54-L58)
- Init-terraform action body (current; baseline for AC1 additive edit): [`.github/actions/init-terraform/action.yml:13-25`](.github/actions/init-terraform/action.yml#L13-L25)
- Init-terraform README (current; baseline for AC1 additive edit): [`.github/actions/init-terraform/README.md`](.github/actions/init-terraform/README.md)
- Outer-tree AWS backend-config file (modified by AC2): [`terraform/konnect-teams/config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend)
- Inner-tree AWS backend-config file (unchanged per AC2): [`.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend)
- Docker-compose MinIO definition (background; auto-creates `tfstate` bucket only): [`docker-compose.yaml:5-37`](docker-compose.yaml#L5-L37)
- `act` host-network config: [`.actrc.tpl`](.actrc.tpl)
- Sprint status: [`sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml)
- Deferred work (pre-existing items Story 2.3 references): [`deferred-work.md`](_bmad-output/implementation-artifacts/deferred-work.md)

### Project Structure Notes

All Story 2.3 changes land at locations the architecture target tree already names ([`architecture.md:347-457`](_bmad-output/planning-artifacts/architecture.md#L347-L457)):

| File | Architecture mapping |
|---|---|
| `.github/actions/init-terraform/action.yml` (modified, AC1) | line 361-362 |
| `.github/actions/init-terraform/README.md` (modified, AC1) | line 361-362 |
| `.github/actions/provision-konnect-resources/action.yaml` (modified, AC4) | line 369 ("consumes init-terraform") |
| `.github/workflows/onboard-konnect-teams.yaml` (modified, AC3) | line 395 ("updated: init-terraform usage") |
| `.github/workflows/developer-portal.yaml` (modified, AC5) | line 394 ("updated: init-terraform usage") |
| `terraform/konnect-teams/config.s3.tfbackend` (modified, AC2) | line 405 ("retained as alt-path") — Story 2.3 bakes the static AWS values per D1 |

Zero conflict or variance from the target tree. The `backend-config-overrides` addition to `init-terraform`'s contract is an **additive** change to the action declared at line 361 — no existing caller is affected, and Story 4.3's lint (when it lands) will accept the new row because it diffs `action.yml` against the README which Story 2.3 keeps in sync.

The pre-existing two-tree split (outer at `terraform/konnect-teams/`, inner at `.github/actions/provision-konnect-resources/terraform/`) is preserved. AC2's asymmetric edit (outer-tree AWS file gets static values baked; inner-tree AWS file stays as a placeholder) is **deliberate** and reflects the inherent asymmetry of the trees (outer is single-team, inner is per-team-invoked). Documented in the file headers via AC2's comment block on the outer file and in AC4's `backend-config-overrides` plumbing for the inner action.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (1M context) via Claude Code, bmad-dev-story workflow.

### Debug Log References

Pre-write byte-equality inventory (Task 1.6, captured 2026-05-12):

```
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  terraform/konnect-teams/config.minio.tfbackend
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend
dfc76d4537a4807d3e11772c8ec1ec20fc89f50604010e49c5a7bf97b40c896e  .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
53717d398158f3bb29b7ba930addc08388faa1f0118d12823cb032b0de48a5b0  .github/workflows/deploy-dp.yaml
0e82953b2c204e5cff9dcbb8f31a20fcff3886596e464dcfc1265859774306d3  .github/workflows/test-sync-api-configuration.yaml
2d01e4ec6ab028674fc1a236f66fd11844ac9198b9d966a4f16f88d4f2467db8  scripts/create-s3-bucket.sh
```

Post-write re-check (Task 9.2) matched all six digests — none of the byte-equality-must-not-change files were touched.

Verification logs (ephemeral, kept under `/tmp/`, not committed):

- `/tmp/init-outer-minio.log` — Task 7 AC6 fallback: `terraform init -reconfigure -input=false -upgrade -backend-config=config.minio.tfbackend` from `terraform/konnect-teams/`. Emitted `Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!` against the local MinIO `tfstate` bucket.
- `/tmp/init-outer-s3.log` — Task 8 AC7 outer-tree forward-compat: AWS env vars + `AWS_ENDPOINT_URL_S3=http://localhost:9000` + `-backend-config=config.s3.tfbackend` + `-backend-config=bucket=tfstate`. rc=0; no `deprecat*` matches.
- `/tmp/init-inner-s3.log` — Task 8 AC7 inner-tree forward-compat: AWS env vars + `-backend-config=config.s3.tfbackend` + `-backend-config=bucket=tfstate` + `-backend-config=region=eu-central-1`. rc=0; no `deprecat*` matches.
- `/tmp/act-2-3-onboard.log` — Task 7 AC6 primary path: `act` failed at `aws-actions/configure-aws-credentials@v4` (`aws-region` input required; `vars.AWS_REGION` unset locally), unreachable to the rewired `Terraform Init` step. Fallback path taken per AC6 alternative; see Completion Notes.

### Completion Notes List

**AC1 (init-terraform action extension):** Added `backend-config-overrides` input (string, optional, default `''`) and rewrote the step body to the array-build pattern (`cmd=(terraform init -reconfigure -input=false -upgrade -backend-config="${{ inputs.backend-config-path }}")` then a `while read … cmd+=(-backend-config="$override")` loop ending in `"${cmd[@]}"`). The verbatim Story 2.2 substring is preserved inside the initial array literal. Description avoids `${{ ... }}` tokens per the Story 2.2 AC3 lesson. README gained one input row, an updated AWS Example Usage block demonstrating the overrides, and a sixth Failure Modes entry on malformed `key=value` lines. P4 H2 structure preserved; README ↔ `action.yml` parity check passes for all three inputs.

**AC2 (outer-tree config.s3.tfbackend):** Baked `bucket = "kw.konnect.teams"`, `region = "eu-central-1"`. `key = "konnect.tfstate"` retained as-was. Header comment added matching `config.minio.tfbackend` style. Inner-tree `config.s3.tfbackend` left untouched per the AC2 carve-out (verified by post-write `shasum -a 256` against the Task 1.6 baseline).

**AC3 (onboard-konnect-teams.yaml):** Added job-level `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` env. Kept `AWS_S3_BUCKET: "kw.konnect.teams"` with a transitional-comment annotation. Gated the `Ensure TF state S3 bucket exists` step with `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'`. Replaced the inline `terraform init` step with `uses: ./.github/actions/init-terraform` (no `backend-config-overrides` — outer tree's values are baked). Step `name: Terraform Init` preserved; no other steps touched. `grep` verification confirms zero residual inline `terraform init` and exactly one `uses: ./.github/actions/init-terraform` reference.

**AC4 (provision-konnect-resources/action.yaml):** Replaced the inline `terraform init` step with `uses: ./.github/actions/init-terraform`, passing `terraform-dir: ${{ github.action_path }}/terraform`, `backend-config-path: ${{ env.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}`, and a YAML literal-block `backend-config-overrides` with two lines (`bucket=kw.konnect.team.resources.${{ inputs.konnect-team-name }}` and `region=${{ inputs.aws-region }}`). The action's `inputs:` block is byte-identical pre and post (no contract change). `Setup Terraform Environment`, `Validate config`, `Setup Terraform`, `Install yq`, and the three Plan/Apply/Destroy steps are byte-identical pre and post.

**AC5 (developer-portal.yaml):** Added job-level `TF_BACKEND_CONFIG` env. Gated `Ensure TF state S3 bucket exists` with `if: env.TF_BACKEND_CONFIG != 'config.minio.tfbackend'`. `AWS_S3_BUCKET: "kw.konnect.dev-portal-terraform-state"` kept as-is (still consumed by the gated step). `Provision Konnect Developer Portal resources` step is byte-identical pre and post. Pre-existing inconsistency between this env and the inner-action per-team bucket noted in deferred-work.md.

**AC6 (act MinIO E2E):** Used the AC6 alternative (lower-effort) verification path. The primary path (`act -W .github/workflows/onboard-konnect-teams.yaml workflow_dispatch`) failed before reaching the rewired `Terraform Init` step, blocked by `aws-actions/configure-aws-credentials@v4` requiring `aws-region` (sourced from `vars.AWS_REGION`, which `act` does not inject). This is a pre-existing local-act gap independent of the Story 2.3 rewire — documented in deferred-work.md for Story 2.5 owner. The fallback executed the rewired `Terraform Init` step body as a direct shell invocation (`terraform init -reconfigure -input=false -upgrade -backend-config=config.minio.tfbackend` from `${TERRAFORM_DIR}`), which emitted both canonical success lines (`Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!`) against the local MinIO `tfstate` bucket. The fallback validates that the action body's MinIO-path init incantation is correct; Plan/Apply paths against the dev Konnect tenant are out-of-scope for this fallback (full E2E is Epic 2.6 territory).

**AC7 (AWS S3 forward-compat):** Both trees exercised the AWS S3 backend code path against MinIO-as-fake-S3 via `AWS_ENDPOINT_URL_S3=http://localhost:9000`. Outer tree (`terraform/konnect-teams/`) with `-backend-config=config.s3.tfbackend -backend-config=bucket=tfstate` returned rc=0 and printed the canonical success messages — confirms the baked AWS values in `config.s3.tfbackend` (AC2) are parseable and the backend connects. Inner tree (`.github/actions/provision-konnect-resources/terraform/`) with `-backend-config=config.s3.tfbackend -backend-config=bucket=tfstate -backend-config=region=eu-central-1` (mirroring what the rewired action's `backend-config-overrides` will pass) also rc=0. No `deprecat*` matches in either log. Both trees cleaned (`.terraform/`, `.terraform.lock.hcl` removed); `AWS_*` env vars not exported to the dev shell.

**AC8 (boundary discipline):** Final `git status --short` matches the expected eight-file set (six source-tree modifications + sprint-status.yaml + this story file + deferred-work.md). All carve-out files re-confirmed byte-identical via `shasum -a 256` against the Task 1.6 baseline. No transient artifacts in `git status`. Sprint-status.yaml `last_updated` (line 2 comment + line 38 YAML key) updated in sync to reflect the `ready-for-dev → in-progress → review` transition. Five deferred items appended to `deferred-work.md` under a new "Deferred from: Story 2.3 implementation (2026-05-12)" section.

**Hand-off note for Story 4.2 (Provision-konnect-resources README):** The inner action now implicitly contracts a `TF_BACKEND_CONFIG` env var from its caller (default `config.minio.tfbackend` if unset). Story 4.2's authored README must document this dependency so out-of-repo callers know to wire it.

### File List

Modified (Story 2.3 deliverables):

- `.github/actions/init-terraform/action.yml` (AC1: new `backend-config-overrides` input + array-build step body)
- `.github/actions/init-terraform/README.md` (AC1: new Inputs row, updated AWS Example Usage, new Failure Modes entry)
- `.github/actions/provision-konnect-resources/action.yaml` (AC4: Terraform Init step rewritten as `uses: ./.github/actions/init-terraform` with per-team overrides)
- `.github/workflows/onboard-konnect-teams.yaml` (AC3: `TF_BACKEND_CONFIG` env, gated bucket step, Init step via action)
- `.github/workflows/developer-portal.yaml` (AC5: `TF_BACKEND_CONFIG` env, gated bucket step)
- `terraform/konnect-teams/config.s3.tfbackend` (AC2: static AWS values baked, header comment added)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (AC8: story status flips + `last_updated`)
- `_bmad-output/implementation-artifacts/2-3-rewire-platform-workflows-to-use-init-terraform-and-tf-backend-config.md` (AC8: Status field, Dev Agent Record, Change Log, task checkboxes)
- `_bmad-output/implementation-artifacts/deferred-work.md` (AC8: new "Deferred from: Story 2.3 implementation (2026-05-12)" section appended)

## Change Log

| Date | Change | Notes |
|---|---|---|
| 2026-05-12 | Story 2.3 implementation complete; status `ready-for-dev → in-progress → review`. | AC1–AC8 satisfied. AC6 used the documented lower-effort fallback path (act blocked by pre-existing `aws-actions/configure-aws-credentials@v4` + `vars.AWS_REGION` gap — surfaced in deferred-work.md). All sha256 byte-equality carve-outs hold. Five new items recorded in deferred-work.md. |
