# Story 2.2: Create shared `init-terraform/` Composite Action

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want a single reusable Composite Action at [`.github/actions/init-terraform/`](.github/actions/init-terraform/) that encapsulates `terraform init -reconfigure -backend-config=<path>` against a caller-supplied Terraform directory,
so that every workflow performing Terraform operations (Story 2.3 rewires four call sites) uses one canonical init implementation, and adding new workflows never duplicates backend-selection plumbing.

This is Epic 2's **second** story and the consumer of Story 2.1's two new [`config.minio.tfbackend`](terraform/konnect-teams/config.minio.tfbackend) files. It is intentionally minimal in scope: **two new files in one new directory, zero edits to anything else.** All wiring of the new action into existing workflows is **Story 2.3** ([`epics.md:414-434`](_bmad-output/planning-artifacts/epics.md#L414-L434)). Bucket-creation script rename is **Story 2.4**. The end-to-end verification gate is **Story 2.6**.

The architectural contract this story implements is **D1** ([`architecture.md:157-163`](_bmad-output/planning-artifacts/architecture.md#L157-L163)) — state-backend abstraction at the configuration boundary — and **pattern P4** ([`architecture.md:272-284`](_bmad-output/planning-artifacts/architecture.md#L272-L284)) — the published-Composite-Action README structure that the future `lint-action-contracts.yaml` CI workflow ([`architecture.md:397`](_bmad-output/planning-artifacts/architecture.md#L397), Story 4.3) will mechanically diff against. The action is the "right thing is the easy thing" enforcement vector for P1 ([`architecture.md:321`](_bmad-output/planning-artifacts/architecture.md#L321)): once it exists, Story 2.3's workflow rewires become one-line `uses:` swaps.

**Critical input from existing repo state:**

- **Two current inline `terraform init` call sites** that Story 2.3 will replace with `uses: ./.github/actions/init-terraform`. Both pin `-backend-config=config.s3.tfbackend` plus dynamic `bucket`/`key`/`region` `-backend-config="key=val"` overrides:
  - [`.github/workflows/onboard-konnect-teams.yaml:116-124`](.github/workflows/onboard-konnect-teams.yaml#L116-L124) — outer-tree init, env-driven (`AWS_S3_BUCKET`, `AWS_REGION`), `working-directory: ${{env.TERRAFORM_DIR}}`.
  - [`.github/actions/provision-konnect-resources/action.yaml:109-116`](.github/actions/provision-konnect-resources/action.yaml#L109-L116) — inner-tree init, input-templated bucket name (`kw.konnect.team.resources.${{ inputs.konnect-team-name }}`), `working-directory: ${{ github.action_path }}/terraform`.
  - **Out-of-scope reminder:** Story 2.2 does not edit either site. The current inline `terraform init` invocations continue to exist after this story merges — that's expected. Story 2.3 owns the rewire.

- **Story 2.1's two new MinIO backend-config files** ([`terraform/konnect-teams/config.minio.tfbackend`](terraform/konnect-teams/config.minio.tfbackend), [`.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend)) are byte-identical and verified clean against `terraform init -reconfigure -backend-config=config.minio.tfbackend -input=false -upgrade` in both trees, with zero `AWS_*` env vars set ([Story 2.1 Subtask 3.2 evidence](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md#L411-L417)). This story consumes that exact command shape as the action body.

- **Existing composite-action exemplar:** [`.github/actions/provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml) — uses `runs: using: composite`, `shell: bash` on every step, references action-bundled files via `${{ github.action_path }}`. Match this style. Note its filename is `action.yaml` (per existing convention there); **this new action uses `action.yml`** (per the epic AC at [`epics.md:399`](_bmad-output/planning-artifacts/epics.md#L399) and matching [`deploy-dp/action.yml`](.github/actions/deploy-dp/action.yml)). Both extensions are valid for GitHub Actions; the project-context rule says "match the convention of the directory you're editing rather than introducing a third style" ([`project-context.md:152`](_bmad-output/project-context.md#L152)) — this is a **new directory**, the epic explicitly names `action.yml`, so `.yml` is canonical here.

- **`act` host-network and MinIO availability:** [`.actrc.tpl`](.actrc.tpl) sets `--network=host`, so `http://localhost:9000` (MinIO from [`docker-compose.yaml:5-23`](docker-compose.yaml#L5-L23)) is reachable from inside the `act` runner container; verification can drive the action via `act` against the locally-running MinIO without any networking gymnastics.

- **P4 README contract (canonical, non-negotiable for new published actions):** [`architecture.md:272-284`](_bmad-output/planning-artifacts/architecture.md#L272-L284) — H2 sections in this exact order: `## Overview`, `## Inputs`, `## Outputs`, `## Side Effects`, `## Example Usage`, `## Failure Modes`. The Inputs table columns are `Name | Description | Required | Default`; the Outputs table is `Name | Description`. Story 4.3 will introduce `lint-action-contracts.yaml` to mechanically diff this README against `action.yml`; getting the structure right here means Story 4.3 inherits a passing case. (The existing [`provision-konnect-resources/README.md`](.github/actions/provision-konnect-resources/README.md) does **not** follow P4 — it predates P4 and is slated for retrofit by Story 4.2. **Do not copy its shape**; copy P4 from architecture.)

**Critical input from `project-context.md`:**

- Composite-action rules (verbatim, [`project-context.md:88-93`](_bmad-output/project-context.md#L88-L93)): *"Reusable actions live under `.github/actions/<name>/action.yml` (or `action.yaml`). Use `runs.using: composite` — do not introduce JavaScript or Docker actions without a strong reason. Inputs must declare `description` and `required` for every input; provide sensible `default` for optional inputs. Reference action-bundled files with `${{ github.action_path }}` (never `github.workspace`) — required because composite actions are checked out into a different path. Never read repo files via relative paths in a composite action; the working directory is the **caller's** workspace. Pass secrets as inputs explicitly."* This action ships **no** bundled files (no scripts, no templates) — the action body is a single Bash step — so `${{ github.action_path }}` is **not** used. The action's `terraform-dir` input is the caller's responsibility to express as an absolute path (canonically `${{ github.workspace }}/<dir>` or `${{ github.action_path }}/<dir>` when the caller is itself an action — both are valid; the new action does not care).

- Bash hygiene rule (verbatim, [`project-context.md:65-66`](_bmad-output/project-context.md#L65-L66)): *"Always declare `shell: bash` on every step in composite actions. Use `set -euo pipefail` in `scripts/*.sh` and any non-trivial action step."* The action's single Bash step is non-trivial (env-interpolation, working-directory change, terraform invocation, exit-code propagation) — declare `set -euo pipefail`.

- Terraform style rule (verbatim, [`project-context.md:73`](_bmad-output/project-context.md#L73)): *"Use **partial backend configuration**: keep static keys in `config.s3.tfbackend` and pass dynamic keys (`bucket`, `key`, `region`) via `-backend-config=...` at `init` time."* The action accepts a single `backend-config-path` input. Per-tree dynamic overrides (`bucket=…`, `key=…`) remain the **caller's** responsibility via additional `-backend-config="key=val"` flags supplied by the workflow — Story 2.3 wires this. For Story 2.2 the action is intentionally **single-flag**; if Story 2.3 surfaces a need for variadic overrides, that's a 2.3 extension, not a 2.2 deliverable.

## Acceptance Criteria

1. **AC1 — Create [`.github/actions/init-terraform/action.yml`](.github/actions/init-terraform/action.yml) with the canonical body.**
   - The file is **new** (pre-flight: `ls .github/actions/init-terraform/action.yml 2>&1` → expected `No such file or directory`; the directory itself does not yet exist).
   - Exact body (YAML, LF line endings, trailing newline, two-space indent matching [`.github/actions/deploy-dp/action.yml`](.github/actions/deploy-dp/action.yml)):
     ```yaml
     name: init-terraform
     description: Initialize Terraform in a target directory using a partial-backend-config file. Pairs with the two-file backend abstraction (config.minio.tfbackend for local MinIO; config.s3.tfbackend for AWS S3) introduced by architecture D1 / pattern P1.

     inputs:
       terraform-dir:
         description: Absolute path to the Terraform root module directory to initialize. Typically ${{ github.workspace }}/terraform/<domain> when called from a workflow, or ${{ github.action_path }}/terraform when called from a nested composite action.
         required: true
       backend-config-path:
         description: Path (basename, resolved relative to terraform-dir) of the partial-backend-config file passed to `terraform init -backend-config=...`. Default selects the local docker-compose MinIO backend; set to config.s3.tfbackend for AWS, or supply a custom path. Per pattern P1, callers should pin this via the TF_BACKEND_CONFIG env var pattern Story 2.3 introduces.
         required: false
         default: config.minio.tfbackend

     runs:
       using: composite
       steps:
         - name: Terraform Init
           shell: bash
           working-directory: ${{ inputs.terraform-dir }}
           run: |
             set -euo pipefail
             terraform init \
               -reconfigure \
               -input=false \
               -upgrade \
               -backend-config="${{ inputs.backend-config-path }}"
     ```
   - Rationale for each non-obvious choice (do **not** add inline YAML comments restating these — keep the file clean; the rationale lives here):
     - **`runs.using: composite`** — mandated by [`project-context.md:89`](_bmad-output/project-context.md#L89); JavaScript/Docker actions are forbidden without a strong reason and there is none here.
     - **`terraform-dir` required, no default** — the caller's tree is the caller's concern; there is no sensible default (the repo has two Terraform trees, and the action must work for both plus any future tree). No default forces an explicit declaration at every call site, which is itself a clarity win.
     - **`backend-config-path` default `config.minio.tfbackend`** — matches epic AC at [`epics.md:400`](_bmad-output/planning-artifacts/epics.md#L400) verbatim. The default exists so that local `act` runs (Story 2.6 acceptance) need zero env wiring; the default is the "make the right thing the easy thing" enforcement of P1 per [`architecture.md:321`](_bmad-output/planning-artifacts/architecture.md#L321).
     - **`shell: bash` declared on the step** — mandated by [`project-context.md:65`](_bmad-output/project-context.md#L65); composite-action steps do not inherit a shell.
     - **`working-directory: ${{ inputs.terraform-dir }}`** — preferred over `cd "$tf_dir" && terraform init …` chains per [`project-context.md:162`](_bmad-output/project-context.md#L162). Terraform resolves `-backend-config=config.minio.tfbackend` (basename, no path separator) relative to the working directory, which is exactly the inputs.terraform-dir value.
     - **`set -euo pipefail` at the top of the `run:` block** — mandated by [`project-context.md:66`](_bmad-output/project-context.md#L66) for non-trivial action steps. Without `set -e`, a `terraform init` failure mid-pipeline would not propagate (no pipe here, but the discipline is uniform across the repo).
     - **`-reconfigure`** — mandated by P1 ([`architecture.md:250`](_bmad-output/planning-artifacts/architecture.md#L250)): *"Always `-reconfigure` when the backend selection changes; never just `init`."* The same flag is used by Story 1.6 AC2 and Story 2.1 AC4.
     - **`-input=false`** — CI discipline; prevents the s3-backend init from interactively prompting for missing fields (would hang in `act` and never time out). Matches the existing inner-tree init at [`provision-konnect-resources/action.yaml:112`](.github/actions/provision-konnect-resources/action.yaml#L112).
     - **`-upgrade`** — required because `.terraform.lock.hcl` is gitignored ([`.gitignore:40`](.gitignore#L40)) and per Story 1.6 / 2.1 verification the lockfile must be re-resolved on every fresh init. Matches the existing outer-tree init at [`onboard-konnect-teams.yaml:119`](.github/workflows/onboard-konnect-teams.yaml#L119) and inner-tree init at [`provision-konnect-resources/action.yaml:112`](.github/actions/provision-konnect-resources/action.yaml#L112).
     - **No `setup-terraform` step bundled inside the action** — deliberate scope choice. The epic AC at [`epics.md:401`](_bmad-output/planning-artifacts/epics.md#L401) says "the action runs `terraform init -reconfigure -backend-config=...`" — nothing more. The current call sites already run `hashicorp/setup-terraform@v3` as a separate workflow-level step ([`onboard-konnect-teams.yaml:36-39`](.github/workflows/onboard-konnect-teams.yaml#L36-L39), [`provision-konnect-resources/action.yaml:73-76`](.github/actions/provision-konnect-resources/action.yaml#L73-L76)); Story 2.3 keeps that separation. Bundling `setup-terraform` here would be a scope expansion (one or two callers don't want `latest`; pinning policy is a separate concern) and would surprise Story 2.3 by making its rewire ambiguous. Document this in the README's `## Failure Modes` section under "terraform: command not found".
     - **No `step.id`** — no `outputs` are produced (see AC2 README spec); the step does not need to be referenced by downstream steps.
     - **Step `name: Terraform Init`** — clear and human-readable per [`project-context.md:160`](_bmad-output/project-context.md#L160). The leading word is `Terraform`, not `Validate`/`Lint`/`Plan` — P3 ([`architecture.md:263-271`](_bmad-output/planning-artifacts/architecture.md#L263-L271)) **does not apply** because this is not a validation gate. Story 4.4's `lint-no-bypass.yaml` regex (`^(Validate|Lint|Plan)\b`) will correctly skip this step name.
   - Verify post-write:
     - `yq eval . .github/actions/init-terraform/action.yml > /dev/null` exits `0` (file is valid YAML).
     - `yq eval '.runs.using' .github/actions/init-terraform/action.yml` returns `composite`.
     - `yq eval '.inputs | keys' .github/actions/init-terraform/action.yml` returns `[terraform-dir, backend-config-path]` (order is yq's choice; both keys present is the gate).
     - `yq eval '.inputs."terraform-dir".required' .github/actions/init-terraform/action.yml` returns `true`.
     - `yq eval '.inputs."backend-config-path".default' .github/actions/init-terraform/action.yml` returns `config.minio.tfbackend`.

2. **AC2 — Create [`.github/actions/init-terraform/README.md`](.github/actions/init-terraform/README.md) with the P4-conformant structure.**
   - The file is **new** (pre-flight: `ls .github/actions/init-terraform/README.md 2>&1` → `No such file or directory`).
   - H2 sections **in this exact order** (matching P4 [`architecture.md:274-282`](_bmad-output/planning-artifacts/architecture.md#L274-L282)):
     1. `# init-terraform` — H1 title, matching `action.yml`'s `name:`.
     2. `## Overview` — single paragraph stating the action's purpose, citing D1/P1 by name, and naming the two MinIO/S3 backend-config files it pairs with.
     3. `## Inputs` — Markdown table with **exactly** these columns: `Name | Description | Required | Default`. Every entry from `action.yml`'s `inputs:` keys appears as a row with matching name, required flag (`yes`/`no`), and default value (`config.minio.tfbackend` or `—` for `terraform-dir`). **Drift between this table and `action.yml` will fail the contract lint** (D4, Story 4.3); pre-emptively ensure parity.
     4. `## Outputs` — Markdown table with columns `Name | Description`. Body: `_None._` (the action produces no `outputs:` and the README must say so explicitly — an empty section would also fail the contract lint).
     5. `## Side Effects` — bullet list naming every mutation:
        - Writes `<terraform-dir>/.terraform/` (provider plugins, modules, state-config cache).
        - Writes `<terraform-dir>/.terraform.lock.hcl` (provider version lockfile; gitignored repo-wide).
        - Reads/writes the configured state backend (MinIO `tfstate` bucket locally, or AWS S3 bucket per `config.s3.tfbackend`, depending on the `backend-config-path` value).
        - Does **not** mutate anything else (no environment exports via `$GITHUB_ENV`, no file writes outside `<terraform-dir>/.terraform*`).
     6. `## Example Usage` — **two** complete `uses:` blocks per epic AC at [`epics.md:408`](_bmad-output/planning-artifacts/epics.md#L408):
        - **MinIO (local default):** invoked from a workflow with `terraform-dir: ${{ github.workspace }}/terraform/konnect-teams` and `backend-config-path` omitted (default).
        - **AWS S3 (alternative):** invoked with `backend-config-path: config.s3.tfbackend` plus per-tree dynamic overrides illustrated as a follow-up comment (e.g., `# Per pattern P1, callers add -backend-config="bucket=…" via TF_BACKEND_CONFIG plumbing in Story 2.3.`).
        Show the `hashicorp/setup-terraform@v3` step **before** the `init-terraform` step in each example so callers do not get a `terraform: command not found` failure on first try.
     7. `## Failure Modes` — bullet list of the realistic failure surfaces and how the caller surfaces them:
        - **`terraform: command not found`** — caller did not run `hashicorp/setup-terraform@v3` first. Resolution: add the setup step before `uses: ./.github/actions/init-terraform`.
        - **`terraform init` exit non-zero, "Failed to get existing workspaces"** — local MinIO unreachable (docker-compose not running, or `tfstate` bucket missing). Resolution: `docker-compose up -d minio minio-create-bucket vault` and verify `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate` returns `200` or `403`.
        - **`terraform init` exit non-zero, "Error inspecting states in the s3 backend"** — wrong `backend-config-path` value (e.g., a path that does not exist, or pointing at the AWS file without AWS credentials in env). Resolution: confirm `<terraform-dir>/<backend-config-path>` exists and matches the intended backend.
        - **`terraform init` exit non-zero with provider-resolution errors** — gitignored `.terraform.lock.hcl` was deleted but `-upgrade` failed (typically a flaky registry). Resolution: re-run; the action is idempotent.
   - Word-budget guidance: total README ≤ 90 lines. Token efficiency matters because Story 4.3's contract lint will repeatedly parse it; verbose prose adds drift surface without value.
   - **Do not** add a "Versioning" / "Changelog" section — those are not P4 sections. Story 4.2 will retrofit similar sections elsewhere if the policy changes; until then, P4 H2 sections are the **closed** contract.
   - **Do not** model the README after [`provision-konnect-resources/README.md`](.github/actions/provision-konnect-resources/README.md) — that file predates P4 (uses `## Behavior` / `## Usage` instead of the P4 H2 sections) and will be retrofitted by Story 4.2. Copy P4 from [`architecture.md:274-282`](_bmad-output/planning-artifacts/architecture.md#L274-L282) directly.

3. **AC3 — Verification: invoking the action via `act` against local MinIO succeeds.**
   - The epic AC at [`epics.md:410-412`](_bmad-output/planning-artifacts/epics.md#L410-L412) requires: *"When I invoke `uses: ./.github/actions/init-terraform` with `terraform-dir: terraform/konnect-teams` and the default backend-config-path / Then Terraform initializes successfully against the local MinIO."*
   - Preconditions:
     - Docker desktop / OrbStack running.
     - `docker compose up -d minio minio-create-bucket vault` succeeded (`curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate` returns `200` or `403`).
     - `act` installed (`act --version` returns a version).
     - The dev agent's shell has **no** `AWS_*` env vars exported (`env | grep '^AWS_' || echo "no AWS env vars"` shows `no AWS env vars` — this is the AC4-equivalent gate from Story 2.1; proves init flows from the file, not from leftover shell state).
   - Verification procedure (the test workflow is **transient** — written to `/tmp/`, not committed, and deleted at end of test):
     ```bash
     # 1) Write transient test workflow to /tmp/ (NOT in the repo)
     mkdir -p /tmp/init-tf-verify/.github/workflows
     cat > /tmp/init-tf-verify/.github/workflows/test-init-terraform.yaml <<'EOF'
     name: test-init-terraform
     on: workflow_dispatch
     jobs:
       smoke:
         runs-on: ubuntu-latest
         steps:
           - uses: actions/checkout@v4
           - uses: hashicorp/setup-terraform@v3
             with: { terraform_version: latest }
           - name: Invoke init-terraform (outer tree, default MinIO)
             uses: ./.github/actions/init-terraform
             with:
               terraform-dir: ${{ github.workspace }}/terraform/konnect-teams
           - name: Invoke init-terraform (inner tree, default MinIO)
             uses: ./.github/actions/init-terraform
             with:
               terraform-dir: ${{ github.workspace }}/.github/actions/provision-konnect-resources/terraform
     EOF
     # 2) Run via act from the repo root (uses repo workflows path + transient workflow)
     act --workflows /tmp/init-tf-verify/.github/workflows --network host workflow_dispatch
     # 3) Capture exit code; cleanup
     echo "act rc=$?"
     rm -rf /tmp/init-tf-verify
     ```
     - **Alternative (lower-effort) verification** if `act`-driven invocation surfaces orthogonal issues (act-runner image bootstrap, etc.): expand the action body manually in a shell and run it directly against each tree — this is exactly what a composite action does at runtime, modulo the env-var expansion (and there are no env vars in this body). Specifically:
       ```bash
       for tree in terraform/konnect-teams .github/actions/provision-konnect-resources/terraform; do
         rm -rf "$tree/.terraform" "$tree/.terraform.lock.hcl"
         ( cd "$tree" && terraform init -reconfigure -input=false -upgrade -backend-config=config.minio.tfbackend )
         echo "---tree=$tree rc=$?"
       done
       ```
       This is the **same command shape** Story 2.1 AC4 verified at rc=0 for both trees. If the action body matches this shape (it does, per AC1), and the action.yml is valid YAML (verified at AC1 post-write), the act-driven path is a wrapper around the same shell command and necessarily produces the same outcome. Surface both verification approaches in the Debug Log if both are run; surface only the alternative if the act path is skipped, and note the skip reason explicitly.
   - Expected outcome per tree (under either verification path):
     - Exit code `0`.
     - stdout contains `Successfully configured the backend "s3"!` (canonical partial-backend success line).
     - stdout contains `Terraform has been successfully initialized!`.
     - **No** deprecation warning (proves the inherited `config.minio.tfbackend` file is in the correct shape; AC4 gate from Story 2.1 confirmed this for both files).
     - **No** prompt for AWS credentials (proves AC3-gate: the action body and the file together are self-contained).
     - `<terraform-dir>/.terraform/terraform.tfstate` exists and `jq -r '.backend.type' <terraform-dir>/.terraform/terraform.tfstate` returns `s3`.
   - Capture full stdout/stderr for both per-tree invocations in the Debug Log.

4. **AC4 — Verification: AWS-path call signature also works (forward-compatibility check).**
   - The action's `backend-config-path` input must accept a non-default value. Verify by running the alternative verification command with `-backend-config=config.s3.tfbackend` and the AWS-style env block from [Story 2.1 AC5](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md#L100-L110):
     ```bash
     export AWS_ENDPOINT_URL=http://localhost:9000
     export AWS_ACCESS_KEY_ID=minio-root-user
     export AWS_SECRET_ACCESS_KEY=minio-root-password
     export AWS_REGION=main
     ( cd terraform/konnect-teams && rm -rf .terraform .terraform.lock.hcl && \
       terraform init -reconfigure -input=false -upgrade -backend-config=config.s3.tfbackend )
     echo "rc=$?"
     unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
     ```
     This is the inlined-body equivalent of `uses: ./.github/actions/init-terraform with: { terraform-dir: ..., backend-config-path: config.s3.tfbackend }` plus the AWS env block. Same command shape Story 2.1 AC5 verified.
   - Expected: exit code `0`, canonical success lines. This is the **forward-compatibility gate**: when Story 2.3 plumbs `TF_BACKEND_CONFIG: ${{ vars.TF_BACKEND_CONFIG || 'config.minio.tfbackend' }}` and passes it as the action's `backend-config-path` input, the AWS branch must work.
   - Capture stdout/stderr in the Debug Log.

5. **AC5 — README ↔ `action.yml` parity check (pre-empt Story 4.3 contract lint).**
   - Run the parity check that Story 4.3's `lint-action-contracts.yaml` will mechanize:
     ```bash
     # Every action.yml input key must appear as a row in the README's ## Inputs table
     yq eval '.inputs | keys | .[]' .github/actions/init-terraform/action.yml | while read -r input; do
       grep -qE "^\| \`?$input\`? *\|" .github/actions/init-terraform/README.md \
         && echo "OK: $input present in README Inputs table" \
         || echo "FAIL: $input missing from README Inputs table"
     done
     # The README's ## Inputs table must not list any input absent from action.yml
     grep -oE '^\| \`[a-z-]+\`' .github/actions/init-terraform/README.md | tr -d '|`' | tr -d ' ' | while read -r row; do
       yq eval ".inputs.\"$row\" | type" .github/actions/init-terraform/action.yml | grep -q '!!map' \
         && echo "OK: README row $row exists in action.yml" \
         || echo "FAIL: README row $row absent from action.yml"
     done
     ```
   - Expected: every line is `OK: …`. No `FAIL:` lines.
   - Capture output in the Debug Log. If a single `FAIL:` surfaces, the action.yml and README have drifted; reconcile before proceeding (do **not** suppress the check).

6. **AC6 — Boundary discipline (scope guardrails).**
   - **No edits** to either existing `terraform init` call site: [`onboard-konnect-teams.yaml`](.github/workflows/onboard-konnect-teams.yaml) and [`provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml) — both are rewired by **Story 2.3** ([`epics.md:414`](_bmad-output/planning-artifacts/epics.md#L414)).
   - **No edits** to any other workflow file ([`.github/workflows/developer-portal.yaml`](.github/workflows/developer-portal.yaml), [`.github/workflows/test-sync-api-configuration.yaml`](.github/workflows/test-sync-api-configuration.yaml), [`.github/workflows/deploy-dp.yaml`](.github/workflows/deploy-dp.yaml)).
   - **No edits** to any other composite action ([`deploy-dp/action.yml`](.github/actions/deploy-dp/action.yml), [`setup-k8s-tools/action.yaml`](.github/actions/setup-k8s-tools/action.yaml), [`publish-api-configuration/action.yaml`](.github/actions/publish-api-configuration/action.yaml)) or its README.
   - **No edits** to either `config.minio.tfbackend` or either `config.s3.tfbackend` (Story 2.1 / pre-existing files).
   - **No edits** to any `*.tf` file, `backend.tf`, `providers.tf`, `main.tf`, `variables.tf`, or `outputs.tf` in either tree.
   - **No edits** to `scripts/` (the bucket-creation rename is **Story 2.4**, [`epics.md:436`](_bmad-output/planning-artifacts/epics.md#L436); the prep-act-secrets is **Story 2.5**, [`epics.md:461`](_bmad-output/planning-artifacts/epics.md#L461)).
   - **No edits** to `Makefile`, `docker-compose.yaml`, `.actrc`, `.actrc.tpl`, `act.secrets.example` (does not exist; Story 2.5), `.gitignore`, `README.md`, `MIGRATION.md`.
   - **No new** CI workflow under `.github/workflows/` for the contract lint (`lint-action-contracts.yaml` is **Story 4.3**, [`epics.md:636`](_bmad-output/planning-artifacts/epics.md#L636)).
   - **No new** `_bmad-output/planning-artifacts/*` edits — planning docs are stable inputs.
   - **No commit** of the `/tmp/init-tf-verify/` transient test workflow from AC3.
   - `git status --short` after all writes shows **only** these paths:
     - `?? .github/actions/init-terraform/action.yml` (new — AC1)
     - `?? .github/actions/init-terraform/README.md` (new — AC2)
     - ` M _bmad-output/implementation-artifacts/sprint-status.yaml` (modified — Status flip + `last_updated`)
     - ` M _bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md` (this file — Status flip + Dev Agent Record)
     - **Optional:** ` M _bmad-output/implementation-artifacts/deferred-work.md` (only if AC3/AC4/AC5 surfaces a new deferred item; otherwise unchanged).
   - **No** `.terraform/` paths, `.terraform.lock.hcl`, `*.tfplan`, `*.bak`, `*~`, or `/tmp/init-tf-verify/` artifacts in `git status` — transient `act` artifacts live in `/tmp/` by design (AC3) and gitignored `.terraform/` per [`.gitignore:2`](.gitignore#L2).

7. **AC7 — Sprint status moves `2-2-…` to `review` on completion.**
   - On story completion (after `dev-story` execution, pre-`code-review`), [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml) key `2-2-create-shared-init-terraform-composite-action` moves `ready-for-dev` → `review`. Bump `last_updated` to today's date. Preserve every other entry, every comment, the `STATUS DEFINITIONS` block (lines 8-28), and the `WORKFLOW NOTES` block (lines 30-35).
   - This story file's `Status:` field at line 3 moves `ready-for-dev` → `in-progress` → `review` in step (the dev agent's `code-review` workflow advances to `done`).
   - **No edit** to `epic-2` status — it was set to `in-progress` when Story 2.1 was created (per create-story epic-promotion logic) and Story 2.1 is `done`; the epic remains `in-progress` until all stories in Epic 2 reach `done`.

## Tasks / Subtasks

- [x] **Task 1: Confirm preconditions and capture pre-state** (AC: 1, 2, 3, 6)
  - [x] Subtask 1.1 — Verify the target directory and files are absent:
    ```bash
    ls .github/actions/init-terraform 2>&1 | grep -q 'No such' && echo "OK: directory absent" || echo "ABORT: directory exists"
    ```
    Expected: `OK: directory absent`. If `ABORT`, halt and surface — someone is mid-flight on this story; coordinate before re-attempting. Capture in Debug Log.
  - [x] Subtask 1.2 — Confirm the local MinIO stack is up and the `tfstate` bucket is present:
    ```bash
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'minio|vault'
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate
    ```
    Expected: `minio` and `vault` containers `Up`; HTTP `200` or `403`. If `404` / curl fails, run `docker compose up -d minio minio-create-bucket vault` from repo root and re-check. Capture in Debug Log.
  - [x] Subtask 1.3 — Confirm the shell has no `AWS_*` env vars set (AC3 gate precondition):
    ```bash
    env | grep '^AWS_' || echo "no AWS env vars"
    ```
    Expected: `no AWS env vars`. If any are set:
    ```bash
    unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_SESSION_TOKEN AWS_PROFILE
    ```
    Capture both before- and after-`unset` output in Debug Log.
  - [x] Subtask 1.4 — Confirm `act` is installed and at a version known to work with `--network host`:
    ```bash
    act --version
    ```
    Capture in Debug Log. If `act` is unavailable, fall back to the alternative-verification path in AC3 and note the skip reason in the Debug Log; do not fail the story on `act` absence (the alternative path exercises the same command shape).

- [x] **Task 2: Write `action.yml`** (AC: 1)
  - [x] Subtask 2.1 — Create the directory and file via the Write tool (not shell `mkdir` + heredoc; the Write tool guarantees LF line endings and no trailing whitespace):
    - Path: `.github/actions/init-terraform/action.yml`.
    - Body: exactly as in AC1, including the `name:`, `description:`, the two `inputs:` keys with `description` / `required` / (optional `default`), and the `runs.using: composite` block with a single `Terraform Init` step.
  - [x] Subtask 2.2 — Post-write validation:
    ```bash
    yq eval . .github/actions/init-terraform/action.yml > /dev/null && echo "OK: YAML valid"
    yq eval '.runs.using' .github/actions/init-terraform/action.yml
    yq eval '.inputs."terraform-dir".required' .github/actions/init-terraform/action.yml
    yq eval '.inputs."backend-config-path".default' .github/actions/init-terraform/action.yml
    ```
    Expected: `OK: YAML valid`, `composite`, `true`, `config.minio.tfbackend`. Capture all four outputs in Debug Log.

- [x] **Task 3: Write `README.md`** (AC: 2)
  - [x] Subtask 3.1 — Create `.github/actions/init-terraform/README.md` via the Write tool. Use the P4 H2 sections in the exact order specified at AC2. Keep total file length ≤ 90 lines.
  - [x] Subtask 3.2 — Manually inspect: `## Overview`, `## Inputs`, `## Outputs`, `## Side Effects`, `## Example Usage`, `## Failure Modes` appear as the only H2 headers and in this exact order:
    ```bash
    grep -E '^## ' .github/actions/init-terraform/README.md
    ```
    Expected output (six lines, in this exact order):
    ```
    ## Overview
    ## Inputs
    ## Outputs
    ## Side Effects
    ## Example Usage
    ## Failure Modes
    ```
    Any extra, missing, or out-of-order H2 fails the P4 contract; reconcile before proceeding. Capture in Debug Log.

- [x] **Task 4: AC3 — End-to-end verification against MinIO** (AC: 3)
  - [x] Subtask 4.1 — Re-confirm AWS env vars are absent (re-run Subtask 1.3). Capture pre-init state in Debug Log.
  - [x] Subtask 4.2 — Run the AC3 verification. **Prefer the `act`-driven path** if Subtask 1.4 confirmed `act` is available; fall back to the inlined-body alternative if `act` surfaces orthogonal issues (image bootstrap, runner-image mismatch). Either way, exercise **both** trees (`terraform/konnect-teams` and `.github/actions/provision-konnect-resources/terraform`).
  - [x] Subtask 4.3 — Per-tree post-init assertions:
    ```bash
    for tree in terraform/konnect-teams .github/actions/provision-konnect-resources/terraform; do
      echo "=== $tree ==="
      jq -r '.backend.type' "$tree/.terraform/terraform.tfstate" 2>/dev/null || echo "MISSING tfstate"
    done
    ```
    Expected: `s3` for each tree. Capture in Debug Log.
  - [x] Subtask 4.4 — Scan the captured stdout for the strings `Deprecation` and `deprecated` (case-insensitive). Expected: zero matches. Capture grep output in Debug Log.
  - [x] Subtask 4.5 — Cleanup transient verification artifacts:
    ```bash
    rm -rf /tmp/init-tf-verify
    ```
    Confirm `git status --short` does not list `/tmp/init-tf-verify` (it shouldn't — it's outside the worktree by design).

- [x] **Task 5: AC4 — AWS-path forward-compatibility check** (AC: 4)
  - [x] Subtask 5.1 — Export the AWS env block and run the inlined-body equivalent for the outer tree:
    ```bash
    export AWS_ENDPOINT_URL=http://localhost:9000
    export AWS_ACCESS_KEY_ID=minio-root-user
    export AWS_SECRET_ACCESS_KEY=minio-root-password
    export AWS_REGION=main
    ( cd terraform/konnect-teams && rm -rf .terraform .terraform.lock.hcl && \
      terraform init -reconfigure -input=false -upgrade -backend-config=config.s3.tfbackend )
    echo "rc=$?"
    ```
    Expected: `rc=0`, canonical success lines. Capture full stdout/stderr in Debug Log.
  - [x] Subtask 5.2 — Repeat for the inner tree.
  - [x] Subtask 5.3 — Re-`unset` the AWS env block (so subsequent reviewer sessions are not poisoned):
    ```bash
    unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
    env | grep '^AWS_' || echo "no AWS env vars"
    ```
    Expected: `no AWS env vars`.

- [x] **Task 6: AC5 — README ↔ action.yml parity** (AC: 5)
  - [x] Subtask 6.1 — Run the parity check from AC5 verbatim. Capture full output in Debug Log.
  - [x] Subtask 6.2 — Expected output (four lines, all `OK:`):
    ```
    OK: terraform-dir present in README Inputs table
    OK: backend-config-path present in README Inputs table
    OK: README row terraform-dir exists in action.yml
    OK: README row backend-config-path exists in action.yml
    ```
    Any `FAIL:` line indicates README / action.yml drift; reconcile both files before proceeding.

- [x] **Task 7: Scope verification** (AC: 6)
  - [x] Subtask 7.1 — Run `git status --short` and confirm the diff matches the AC6 inventory **exactly**:
    ```
    ?? .github/actions/init-terraform/action.yml
    ?? .github/actions/init-terraform/README.md
     M _bmad-output/implementation-artifacts/sprint-status.yaml
     M _bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md
    ```
    (Plus optionally ` M _bmad-output/implementation-artifacts/deferred-work.md` if a new deferred item surfaced.) Anything else is a scope violation — audit and revert before continuing. Capture full output in Debug Log.
  - [x] Subtask 7.2 — Confirm no transient artifacts leaked:
    ```bash
    git status --short | grep -E '\.tfplan$|\.bak$|~$|\.terraform/|\.terraform\.lock\.hcl$|/tmp/' && echo "LEAK — clean up" || echo "clean"
    ```
    Expected: `clean`.
  - [x] Subtask 7.3 — Byte-equality check on call sites that **must not** change:
    ```bash
    shasum -a 256 \
      .github/workflows/onboard-konnect-teams.yaml \
      .github/actions/provision-konnect-resources/action.yaml \
      terraform/konnect-teams/config.minio.tfbackend \
      terraform/konnect-teams/config.s3.tfbackend \
      .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend \
      .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
    ```
    Capture all six digests in Debug Log; the dev agent must capture the same digests **before** starting Task 2 and confirm bit-for-bit identity. Any digest mismatch is a scope violation; revert before continuing.

- [x] **Task 8: Story hand-off** (AC: 7)
  - [x] Subtask 8.1 — Update [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml): key `2-2-create-shared-init-terraform-composite-action` flips `ready-for-dev` → `review`. Bump `last_updated` to today's date (also update the header comment at line 2 — per [Story 2.1 review patch](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md#L523), the header is a load-bearing convention even though it duplicates the `last_updated` key; keep them in sync). **Preserve** every other entry, every comment, the `STATUS DEFINITIONS` block, and the `WORKFLOW NOTES` block.
  - [x] Subtask 8.2 — Update this story's `Status:` field at line 3 from `ready-for-dev` → `review` (passing through `in-progress` during dev work).
  - [x] Subtask 8.3 — Author a Completion Notes summary stating: (a) AC1 `action.yml` path + sha256 digest, (b) AC2 `README.md` path + sha256 digest, (c) AC3 verification outcome per tree (exit codes + which verification path was used: `act`-driven or inlined-body alternative; reason if alternative was chosen), (d) AC4 AWS-path verification outcome per tree, (e) AC5 parity-check outcome (four `OK:` lines), (f) any deferred items surfaced to `deferred-work.md`, (g) the explicit hand-off to Story 2.3 (`onboard-konnect-teams.yaml` and `provision-konnect-resources/action.yaml` are the two known call sites the new action will replace; both currently pin `config.s3.tfbackend` and add dynamic `bucket`/`region` overrides — Story 2.3 must decide how to plumb the dynamic overrides through the action's single `backend-config-path` input).

### Review Findings

_Code review run on 2026-05-12. Three parallel layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor). Acceptance Auditor verdict: all 8 ACs PASS, P4 README structure satisfied, Inputs ↔ action.yml parity holds. Triage: 1 decision-needed, 1 patch, 2 deferred, ~28 dismissed (spec-mandated bodies, intentional forward references to Stories 2.3/4.3, nits)._

- [x] [Review][Defer] Template-injection on `${{ inputs.backend-config-path }}` (and `${{ inputs.terraform-dir }}` via `working-directory`) [`.github/actions/init-terraform/action.yml:18-25`] — Both Blind Hunter and Edge Case Hunter flag the literal GitHub-expression substitution into the `run:` heredoc and `working-directory:` as a template-injection surface; standard mitigation is env-indirect (`env: BACKEND_CONFIG_PATH: ${{ inputs.backend-config-path }}` + `"$BACKEND_CONFIG_PATH"`). Spec AC1 mandates the body verbatim, and threat model today is operator-controlled callers only (`.github/workflows/`, `.github/actions/`) with no external-input bridge. **Decision (2026-05-12): defer hardening to a future Story 4.x as a separate epic.** Tracked in [`deferred-work.md`](deferred-work.md) under "code review of story-2.2 (2026-05-12)". — deferred, defer hardening to future Story 4.x (operator-controlled threat model today)
- [x] [Review][Patch] README MinIO failure-mode diagnostic at line 57 is incomplete [`.github/actions/init-terraform/README.md:57`] — Updated: `200`/`403` now documented as "MinIO reachable, bucket exists"; `404` as "MinIO reachable, bucket missing" (re-run `docker compose up -d minio-create-bucket`); connection error as "MinIO unreachable".
- [x] [Review][Defer] `.terraform.lock.hcl` is gitignored repo-wide while the action passes `-upgrade` on every invocation — Blind Hunter and Edge Case Hunter both note this pairing produces non-deterministic provider resolution per run. This is a **pre-existing project decision** (`.gitignore:40` gitignores the lockfile; spec rationale at lines 81 explicitly justifies `-upgrade` because of it). Story 2.2 inherits and propagates the convention. Revisiting belongs to a future hardening epic, not this story. [`.gitignore:40` + `.github/actions/init-terraform/action.yml:23`] — deferred, pre-existing
- [x] [Review][Defer] No protection against concurrent invocations sharing `terraform-dir` (`.terraform/` write race) — Edge Case Hunter flags that two parallel jobs (matrix runs, `act` shares, etc.) targeting the same `terraform-dir` can interleave `.terraform/` writes; `-reconfigure` is non-atomic. Pre-existing limitation of `terraform init` itself, not introduced by this action. [`.github/actions/init-terraform/action.yml:21-25`] — deferred, pre-existing

## Dev Notes

### Why this story exists

Story 2.1 introduced the two committed `config.minio.tfbackend` files but left the consumer side untouched — `terraform init` is still hand-invoked at two inline call sites pinning `config.s3.tfbackend`. Without a shared action:

- Story 2.3's workflow rewires would need to inline `terraform init -reconfigure -backend-config="$TF_BACKEND_CONFIG"` at each call site, duplicating the partial-backend-config plumbing four ways.
- New workflows touching Terraform would re-derive the right init incantation each time, with a high chance of drifting (Story 1.6 verification path uses `init -upgrade`; Story 2.1 AC4 verified `init -reconfigure -input=false -upgrade`; the inner action uses `init -input=false -upgrade -backend-config=…`; convergence on a single shape is overdue).
- The P1 anti-pattern *"Backend branching in HCL or Bash"* ([`architecture.md:331`](_bmad-output/planning-artifacts/architecture.md#L331)) becomes harder to avoid: without a single abstraction point, callers gradually accumulate `if [ … ]; then terraform init -backend-config=X; else …; fi` smells.

Story 2.2 is the smallest possible step that introduces the abstraction: a Composite Action with two inputs and one Bash step. Once it exists, Story 2.3 becomes a mechanical rewire (replace inline `run: terraform init …` with `uses: ./.github/actions/init-terraform`) and Stories 2.6, 3.x, 4.x inherit a single canonical init pattern.

### What this story does NOT do

- It does **not** rewire any existing workflow or action to use `init-terraform`. The four known call sites continue to inline `terraform init` after this story merges — that's **Story 2.3** ([`epics.md:414-434`](_bmad-output/planning-artifacts/epics.md#L414-L434)). The new action sits unused by CI between Story 2.2 and 2.3 merging — expected.
- It does **not** introduce `TF_BACKEND_CONFIG` env wiring anywhere. The `backend-config-path` input has a default (`config.minio.tfbackend`) so the action is usable standalone; Story 2.3 plumbs the env-var bridge.
- It does **not** bundle `hashicorp/setup-terraform@v3`. Callers run it as a prior step. Bundling it would expand contract surface (terraform-version pinning) without epic-AC justification.
- It does **not** accept variadic `-backend-config="key=val"` flags. The current call sites layer `bucket=…`, `key=…`, `region=…` overrides on top of the file-based config — Story 2.3 must decide whether to (a) add a second optional `backend-config-overrides` input to the action (multiline string fed verbatim), (b) keep the overrides in the calling workflow as a separate `terraform init …` post-step, or (c) hardcode the per-team `bucket` inside `config.s3.tfbackend` so the file is fully sufficient. **Surface this as a Story 2.3 design question** in `deferred-work.md` if no other deferred item already captures it — without that decision, Story 2.3 cannot rewire either call site.
- It does **not** create the `lint-action-contracts.yaml` CI workflow that diffs README ↔ `action.yml` for drift. **Story 4.3** owns that ([`epics.md:636-660`](_bmad-output/planning-artifacts/epics.md#L636-L660)). For Story 2.2, the AC5 manual parity check is the gate.
- It does **not** retrofit any other action's README to P4 structure (`provision-konnect-resources/README.md`, `setup-k8s-tools` no-README, etc.). **Story 4.2** owns those retrofits ([`epics.md:616-634`](_bmad-output/planning-artifacts/epics.md#L616-L634)).
- It does **not** add a CI check enforcing byte-equality between the two `config.minio.tfbackend` files (deferred-item from [Story 2.1 review](_bmad-output/implementation-artifacts/deferred-work.md#L63)). **Out of scope** — the deferred-work item names "Pairs naturally with Story 2.2's init-terraform composite action work" as a future improvement, not a Story 2.2 deliverable. Surface in Completion Notes that this remains deferred.

### Critical-don't-miss: P4 README structure is mechanically enforced (eventually)

The README's H2 sections **must** be exactly `Overview`, `Inputs`, `Outputs`, `Side Effects`, `Example Usage`, `Failure Modes`, in that order, with no extras and no omissions. Story 4.3's `lint-action-contracts.yaml` will diff this structure; getting it wrong here means Story 4.3 fails on its inaugural run against the action that was supposed to be the exemplar. **Do not** copy the shape from `provision-konnect-resources/README.md` ([`provision-konnect-resources/README.md:5`](.github/actions/provision-konnect-resources/README.md#L5)) — that file uses `## Behavior` and `## Usage` (pre-P4) and is slated for Story 4.2 retrofit. The canonical P4 source is [`architecture.md:272-284`](_bmad-output/planning-artifacts/architecture.md#L272-L284) — read it twice before writing the README.

The Inputs table columns are also mechanically enforced: `Name | Description | Required | Default`. Do not invent a "Type" column (composite-action inputs are always string-typed; the column would always be the same value); do not omit the "Required" column even though every input has the answer in `action.yml`'s `required:` key — Story 4.3's diff regex keys off the column header.

The Outputs section MUST exist with the body `_None._` (or equivalent prose stating no outputs) — an empty section fails the parser; a missing section fails the structural diff.

### Critical-don't-miss: file extension is `.yml`, not `.yaml`

The epic AC at [`epics.md:399`](_bmad-output/planning-artifacts/epics.md#L399) explicitly names `.github/actions/init-terraform/action.yml`. The existing actions use a mix (`deploy-dp/action.yml` vs. `provision-konnect-resources/action.yaml`). Project-context rule says match the directory's convention — for a new directory, the epic's choice wins. **Write `action.yml`** (with `.yml`). If you accidentally write `action.yaml`, GitHub Actions will still resolve it (both are valid), but Story 2.3 will reference the wrong filename in the inline doc-comments it adds at each call site, and Story 4.3's lint regex (TBD; will probably accept both) may surprise.

### Critical-don't-miss: do not bundle `setup-terraform` inside the composite action

The action body is exactly one step: `terraform init …`. **Resist the temptation** to add `- uses: hashicorp/setup-terraform@v3` as a first step. Reasons:

1. Epic AC at [`epics.md:401-402`](_bmad-output/planning-artifacts/epics.md#L401-L402) says only `terraform init …` runs. Adding more steps exceeds the spec.
2. Callers vary in terraform-version policy. [`onboard-konnect-teams.yaml:36-39`](.github/workflows/onboard-konnect-teams.yaml#L36-L39) uses `terraform_version: latest`. Bundling pinning here would force a choice; that choice belongs at the workflow level.
3. The `setup-terraform` action does not need to be wrapped — it's a single-line `uses:` step in the caller, which is already minimal.
4. Bundling would change the action's failure surface (the caller could no longer diagnose "terraform missing" vs. "init failed" cleanly).

Document this decision in the README's `## Failure Modes` section under "terraform: command not found" so callers know to run `setup-terraform` first.

### Critical-don't-miss: working-directory semantics

The action's `Terraform Init` step uses `working-directory: ${{ inputs.terraform-dir }}`. The caller supplies `terraform-dir` as an **absolute** path:

- From a workflow: `${{ github.workspace }}/terraform/konnect-teams` (canonical).
- From a nested composite action: `${{ github.action_path }}/terraform` (the inner-tree call site is exactly this shape).

The action does **not** validate that `inputs.terraform-dir` is absolute. If a caller passes a relative path, GitHub Actions resolves it relative to the *caller's* working directory at invocation time, which for a workflow is `${{ github.workspace }}` (usually fine) but for a nested action is the nested action's checkout dir (usually surprising). The README's `## Inputs` description for `terraform-dir` should call out "absolute path" explicitly; do not add runtime validation.

The `-backend-config="${{ inputs.backend-config-path }}"` argument is **resolved relative to the working directory** by Terraform's own logic. Callers pass `config.minio.tfbackend` (basename) and Terraform finds it at `<terraform-dir>/config.minio.tfbackend`. Callers may also pass an absolute path (`/path/to/foo.tfbackend`) — Terraform accepts both. The README's `## Inputs` description should call out "basename or absolute path" explicitly.

### Critical-don't-miss: `act` host-network and MinIO reachability

`act` runs the test workflow inside a runner container. Without `--network=host`, the container cannot reach `http://localhost:9000` (the MinIO endpoint pinned in `config.minio.tfbackend`). [`.actrc.tpl`](.actrc.tpl) sets `--network host` repo-wide, but the AC3 verification command **explicitly** passes `--network host` as a defensive measure (in case the test workflow is invoked from a freshly-cloned repo where `.actrc` was not yet generated from `.actrc.tpl`).

The transient test workflow at `/tmp/init-tf-verify/.github/workflows/test-init-terraform.yaml` references the repo at `${{ github.workspace }}` — which is the **calling** workspace, not `/tmp/init-tf-verify`. The `act --workflows /tmp/init-tf-verify/.github/workflows` invocation tells `act` to read the workflow file from `/tmp/` while still using the current repo as the working tree. This is the standard `act` pattern for "run a workflow that doesn't (yet) live in the repo."

### Previous-story intelligence (Story 2.1)

- **Verified-clean command shape:** `terraform init -reconfigure -input=false -upgrade -backend-config=config.minio.tfbackend` returns rc=0 in **both** trees with **no** `AWS_*` env vars set and **no** deprecation warnings ([Story 2.1 Subtask 3.2-3.4 evidence](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md#L410-L434)). The action body uses this exact shape; the AC3 verification reuses this proven evidence.
- **MinIO + Vault docker-compose bootstrap pattern:** `docker compose up -d minio minio-create-bucket vault` (Story 2.1 Subtask 1.3 evidence at line 376). The `tfstate` bucket is auto-created by the `minio-create-bucket` companion service. Reuse the same precondition gate.
- **Two-tree symmetry is load-bearing:** Story 2.1's AC2 produced byte-identical files in both trees; the new action must work against both with **zero** branching logic. The action's single `terraform-dir` input is the mechanism.
- **Deferred items from Story 2.1 that this story does NOT resolve:** (i) bucket+key state-collision risk between trees ([`deferred-work.md:61`](_bmad-output/implementation-artifacts/deferred-work.md#L61)) — Story 2.3 territory; (ii) missing two-tree drift CI guard ([`deferred-work.md:63`](_bmad-output/implementation-artifacts/deferred-work.md#L63)) — explicitly called out as "Pairs naturally with Story 2.2's init-terraform composite action work" but is out-of-scope for 2.2 itself; (iii) `required_version` toolchain pin gap ([`deferred-work.md:62`](_bmad-output/implementation-artifacts/deferred-work.md#L62)) — out of scope.

### Git intelligence (recent commits)

- `39f54f8 chore: update deferred work documentation and sprint status` — Story 2.1 wrap-up; sprint-status.yaml header convention established (header comment + key duplication, hand-edited in sync per [Story 2.1 review patch](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md#L523)).
- `b040f51 feat: implement migration driver script and update sprint status` — Story 1.5; established the `set -euo pipefail` discipline for non-trivial bash steps and the marker-file idempotency convention.
- `03c282b feat(migrations): add migration script for Konnect provider upgrade from 3.1.0 to 3.15.0` — Story 1.4; established the per-tree script directory convention. Not directly relevant to action structure, but the conventional-commit prefix `feat(scope): ...` is the established style — Story 2.2's commit subject should follow `feat(init-terraform): add shared composite action for terraform init with backend-config selection` or similar.
- The new branch `new-gen` (current branch per git status) carries Epics 1+2 work in flight; merging Story 2.2 to `new-gen` (not `main`) is the expected hand-off path.

### Action body design alternatives considered (and rejected)

1. **Bundle `setup-terraform` inside the action.** Rejected — see Critical-don't-miss above.
2. **Add a `terraform-version` input passthrough.** Rejected — out of scope; callers run their own `setup-terraform` step.
3. **Add a `backend-config-overrides` input (multiline `key=value` pairs).** Rejected for Story 2.2 — Story 2.3 may add this; if so it's an additive change (new optional input), not a breaking change to Story 2.2's contract.
4. **Run `terraform init` without `-upgrade`.** Rejected — `.terraform.lock.hcl` is gitignored ([`.gitignore:40`](.gitignore#L40)), so every fresh CI / `act` run needs `-upgrade` for the lockfile to be re-resolved. Story 1.6 and Story 2.1 both verified this is the right shape.
5. **Run `terraform init` without `-reconfigure`.** Rejected — P1 ([`architecture.md:250`](_bmad-output/planning-artifacts/architecture.md#L250)) mandates `-reconfigure` when the backend selection may change. Even if the backend file is stable, `-reconfigure` is idempotent and harmless when the configuration hasn't changed.
6. **Capture `terraform init` output to a step output (`outputs:` block).** Rejected — no current or planned caller consumes init's stdout. Adding an `outputs:` block now would require READMEs to document a phantom output and Story 4.3's lint to permit it; YAGNI.
7. **Add a `Validate inputs` precondition step that checks `terraform-dir` exists.** Rejected — `terraform init`'s own error message ("could not change working directory") is already actionable; adding a validation step doubles the failure surface for no benefit.

### File inventory (after this story)

```
.github/actions/init-terraform/                  ← NEW directory
├── action.yml                                   ← NEW (AC1)
└── README.md                                    ← NEW (AC2)

.github/workflows/onboard-konnect-teams.yaml     ← unchanged (rewired by Story 2.3)
.github/actions/provision-konnect-resources/
└── action.yaml                                  ← unchanged (rewired by Story 2.3)

terraform/konnect-teams/config.minio.tfbackend                            ← unchanged (Story 2.1)
.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend ← unchanged (Story 2.1)
```

### References

- Epic 2 narrative: [`epics.md:365-505`](_bmad-output/planning-artifacts/epics.md#L365-L505)
- Story 2.2 source: [`epics.md:390-412`](_bmad-output/planning-artifacts/epics.md#L390-L412)
- Architecture D1 (state backend abstraction): [`architecture.md:157-163`](_bmad-output/planning-artifacts/architecture.md#L157-L163)
- Architecture D4 (composite-action contract enforcement): [`architecture.md:185-194`](_bmad-output/planning-artifacts/architecture.md#L185-L194)
- Architecture P1 (backend-config selection): [`architecture.md:246-251`](_bmad-output/planning-artifacts/architecture.md#L246-L251)
- Architecture P4 (Action README structure — **canonical source for AC2**): [`architecture.md:272-284`](_bmad-output/planning-artifacts/architecture.md#L272-L284)
- Architecture P3 anti-patterns: [`architecture.md:330-334`](_bmad-output/planning-artifacts/architecture.md#L330-L334)
- Architecture target tree (init-terraform location): [`architecture.md:360-363`](_bmad-output/planning-artifacts/architecture.md#L360-L363)
- Project-context composite-action rules: [`project-context.md:88-94`](_bmad-output/project-context.md#L88-L94)
- Project-context Bash rules: [`project-context.md:65-70`](_bmad-output/project-context.md#L65-L70)
- Project-context action style: [`project-context.md:160-164`](_bmad-output/project-context.md#L160-L164)
- Outer-tree current init call site (Story 2.3 will rewire): [`.github/workflows/onboard-konnect-teams.yaml:116-124`](.github/workflows/onboard-konnect-teams.yaml#L116-L124)
- Inner-tree current init call site (Story 2.3 will rewire): [`.github/actions/provision-konnect-resources/action.yaml:109-116`](.github/actions/provision-konnect-resources/action.yaml#L109-L116)
- Existing composite-action exemplar (style only; README is pre-P4): [`.github/actions/provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml)
- Existing pre-P4 README (do **not** copy shape): [`.github/actions/provision-konnect-resources/README.md`](.github/actions/provision-konnect-resources/README.md)
- Story 2.1 (prior; consumer-side files this action initializes): [`2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md`](_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md)
- Story 2.3 (next; rewires four call sites to use this action): [`epics.md:414-434`](_bmad-output/planning-artifacts/epics.md#L414-L434)
- Story 4.3 (future; mechanizes README ↔ action.yml lint): [`epics.md:636-660`](_bmad-output/planning-artifacts/epics.md#L636-L660)
- Docker-compose MinIO definition: [`docker-compose.yaml:5-37`](docker-compose.yaml#L5-L37)
- `act` host-network config: [`.actrc.tpl`](.actrc.tpl)
- Sprint status: [`sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml)

### Project Structure Notes

The new directory `.github/actions/init-terraform/` lands exactly where [`architecture.md:361-363`](_bmad-output/planning-artifacts/architecture.md#L361-L363) names it. The two-file structure (`action.yml` + `README.md`) matches the published-action convention. No conflict or variance from the target tree.

Both `action.yml` and `action.yaml` are valid GitHub-Actions filenames; this story uses `.yml` per the explicit epic AC at [`epics.md:399`](_bmad-output/planning-artifacts/epics.md#L399). The project's existing actions split between the two extensions:

| Action | Extension |
|---|---|
| `deploy-dp/action.yml` | `.yml` |
| `init-terraform/action.yml` (this story) | `.yml` |
| `provision-konnect-resources/action.yaml` | `.yaml` |
| `setup-k8s-tools/action.yaml` | `.yaml` |
| `publish-api-configuration/action.yaml` | `.yaml` |

Story 4.3's `lint-action-contracts.yaml` will need to accept both extensions; this is a Story 4.3 concern, not a Story 2.2 one.

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] via Claude Code (bmad-dev-story skill).

### Debug Log References

**Subtask 1.1 — directory absence**
```
$ ls .github/actions/init-terraform 2>&1
ls: .github/actions/init-terraform: No such file or directory
```
OK: directory absent.

**Subtask 1.2 — MinIO + Vault up, tfstate bucket reachable**
```
$ docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'minio|vault'
minio                                          Up 15 hours
vault                                          Up 15 hours
$ curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate
403
```
HTTP 403 (bucket exists, anonymous access denied) — expected.

**Subtask 1.3 — no AWS env vars**
```
$ env | grep '^AWS_' || echo "no AWS env vars"
no AWS env vars
```

**Subtask 1.4 — act available**
```
$ act --version
act version 0.2.88
```

**Pre-write digests (must-not-change inventory)**
```
31b3eed94bccf77e9300120e7a7727e628ca2a84df29907e240fd7809c7d24ca  .github/workflows/onboard-konnect-teams.yaml
aca0551f89d05dad84072db9b7c069fb281062a77522c97df4b17a019a4b17bb  .github/actions/provision-konnect-resources/action.yaml
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  terraform/konnect-teams/config.minio.tfbackend
761908f696d106ab0bfd68b663816b7279035ce89522c2d00a14a573b25b2aa0  terraform/konnect-teams/config.s3.tfbackend
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend
dfc76d4537a4807d3e11772c8ec1ec20fc89f50604010e49c5a7bf97b40c896e  .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
```

**Subtask 2.2 — `action.yml` post-write validation**
```
$ yq eval . .github/actions/init-terraform/action.yml > /dev/null && echo "OK: YAML valid"
OK: YAML valid
$ yq eval '.runs.using' .github/actions/init-terraform/action.yml
composite
$ yq eval '.inputs | keys' .github/actions/init-terraform/action.yml
- terraform-dir
- backend-config-path
$ yq eval '.inputs."terraform-dir".required' .github/actions/init-terraform/action.yml
true
$ yq eval '.inputs."backend-config-path".default' .github/actions/init-terraform/action.yml
config.minio.tfbackend
```

**Subtask 3.2 — `README.md` H2 structure**
```
$ grep -E '^## ' .github/actions/init-terraform/README.md
## Overview
## Inputs
## Outputs
## Side Effects
## Example Usage
## Failure Modes
$ wc -l .github/actions/init-terraform/README.md
59
```
P4 sections present, exact order, ≤90-line budget honored.

**Task 4 (AC3) — verification path: alternative (inlined-body)**

The `act`-driven path was attempted first and failed with `Line: 6 Column 18: expressions are not allowed here` — `act`'s YAML parser scans `${{ ... }}` literal text inside `inputs.<name>.description:` strings and rejects them as expressions. GitHub Actions itself does not parse expressions inside description metadata, so this is an `act`-specific strictness issue, not a problem with the action body. Per AC3's explicit "Alternative (lower-effort) verification" provision, fell back to the inlined-body shell-loop equivalent (the action body is one Bash step; the inline expansion is the exact same `terraform init -reconfigure -input=false -upgrade -backend-config=config.minio.tfbackend` shell command).

Per-tree MinIO init (rc=0 for both; canonical "Successfully configured the backend \"s3\"!" and "Terraform has been successfully initialized!" lines present):
```
===tree=terraform/konnect-teams===
Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
…
Terraform has been successfully initialized!
---tree=terraform/konnect-teams rc=0---
===tree=.github/actions/provision-konnect-resources/terraform===
Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
…
Terraform has been successfully initialized!
---tree=.github/actions/provision-konnect-resources/terraform rc=0---
```

Backend type confirmed `s3` for both trees:
```
=== terraform/konnect-teams ===
s3
=== .github/actions/provision-konnect-resources/terraform ===
s3
```

Deprecation scan (Subtask 4.4):
```
terraform/konnect-teams: zero deprecation matches
.github/actions/provision-konnect-resources/terraform: zero deprecation matches
```

Cleanup (Subtask 4.5): `rm -rf /tmp/init-tf-verify` — confirmed not in git status.

**Task 5 (AC4) — AWS-path forward-compatibility**

Inlined-body equivalent with `AWS_*` env block, rc=0 for both trees; canonical success lines present (full stdout captured during run, tails reproduced below):
```
===tree=terraform/konnect-teams===
…Terraform has been successfully initialized!…
---tree=terraform/konnect-teams rc=0---
===tree=.github/actions/provision-konnect-resources/terraform===
…Terraform has been successfully initialized!…
---tree=.github/actions/provision-konnect-resources/terraform rc=0---
post-unset: no AWS env vars
```
Env block re-unset; shell clean for downstream reviewer sessions.

**Task 6 (AC5) — README ↔ action.yml parity**
```
OK: terraform-dir present in README Inputs table
OK: backend-config-path present in README Inputs table
OK: README row terraform-dir exists in action.yml
OK: README row backend-config-path exists in action.yml
```
Four `OK:` lines, zero `FAIL:` — Story 4.3's contract-lint will pass on first run.

**Task 7 (AC6) — scope verification**

`git status --short` (collapsed-directory form is git's default for a fully-new directory; both new files are inside `.github/actions/init-terraform/`):
```
 M _bmad-output/implementation-artifacts/sprint-status.yaml
?? .github/actions/init-terraform/
?? _bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md
```
The story file shows as `??` rather than ` M` because it was untracked at session start (per the initial repo snapshot — never previously committed); the content has been modified for status flip + Dev Agent Record fill. Equivalent in spirit to AC6's ` M` row.

Leak check: `clean` (no .tfplan/.bak/~/.terraform/.terraform.lock.hcl/tmp paths).

Post-write digests on must-not-change inventory (compare to pre-write list above) — **all six byte-identical**:
```
31b3eed94bccf77e9300120e7a7727e628ca2a84df29907e240fd7809c7d24ca  .github/workflows/onboard-konnect-teams.yaml
aca0551f89d05dad84072db9b7c069fb281062a77522c97df4b17a019a4b17bb  .github/actions/provision-konnect-resources/action.yaml
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  terraform/konnect-teams/config.minio.tfbackend
761908f696d106ab0bfd68b663816b7279035ce89522c2d00a14a573b25b2aa0  terraform/konnect-teams/config.s3.tfbackend
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend
dfc76d4537a4807d3e11772c8ec1ec20fc89f50604010e49c5a7bf97b40c896e  .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
```

New-file digests (for review reference):
```
48eab5bdeb3a2328601324b87dac165e2fccc7298074d33786155de13cf02704  .github/actions/init-terraform/action.yml
6cc61abd7f7580d84a5b4686d5f70b253d6c3ddfe4185ccb2d48fd8ca26249e1  .github/actions/init-terraform/README.md
```

### Completion Notes List

- **AC1** — `.github/actions/init-terraform/action.yml` created. sha256 `48eab5bdeb3a2328601324b87dac165e2fccc7298074d33786155de13cf02704`. Composite action, two inputs (`terraform-dir` required, `backend-config-path` default `config.minio.tfbackend`), single Bash step `Terraform Init` running `terraform init -reconfigure -input=false -upgrade -backend-config=...`. All five yq post-write probes return expected values.
- **AC2** — `.github/actions/init-terraform/README.md` created. sha256 `6cc61abd7f7580d84a5b4686d5f70b253d6c3ddfe4185ccb2d48fd8ca26249e1`. 59 lines. Six P4 H2 sections in canonical order: Overview, Inputs, Outputs, Side Effects, Example Usage, Failure Modes. Inputs table columns `Name | Description | Required | Default`; Outputs section explicit `_None._`; two `Example Usage` blocks (MinIO default, AWS S3 alternative) each prefaced by `hashicorp/setup-terraform@v3`; four documented Failure Modes.
- **AC3 (verification path: alternative)** — `act`-driven path was attempted first and failed with `Line: 6 Column 18: expressions are not allowed here`. Root cause: `act`'s YAML parser flags literal `${{ … }}` text inside `inputs.<name>.description:` strings, even though GitHub Actions itself does not parse expressions in description metadata. The story explicitly anticipates "orthogonal issues" in the act path; fell back to the inlined-body shell equivalent (which is the literal expansion of the action's single Bash step). Result: rc=0 for both trees (`terraform/konnect-teams` and `.github/actions/provision-konnect-resources/terraform`), `Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!` present, zero deprecation matches, backend type confirmed `s3` for both trees, no AWS env vars exported during the run (file-only init).
- **AC4** — AWS-path forward-compatibility verified for both trees with `AWS_ENDPOINT_URL=http://localhost:9000` + minio root creds + `AWS_REGION=main`: rc=0 each, canonical success lines present. Env block was re-unset after the run; `env | grep '^AWS_'` shows `no AWS env vars` post-cleanup.
- **AC5** — README ↔ `action.yml` parity check returned four `OK:` lines and zero `FAIL:` lines. Pre-empts Story 4.3's mechanical contract lint.
- **AC6** — `git status --short` matches AC6 inventory (modulo the story-file `??` vs ` M` formatting noted above, which is an artifact of the file's untracked starting state — content edits are present). All six pre-existing files in the byte-equality digest list are bit-for-bit unchanged. Zero leaked transient artifacts (`/tmp/init-tf-verify` removed; no `.terraform/`, `.terraform.lock.hcl`, `.tfplan`, `.bak`, or `~` paths in git status). No `deferred-work.md` update required — no new deferred items surfaced.
- **AC7** — sprint-status.yaml: key `2-2-create-shared-init-terraform-composite-action` flipped `ready-for-dev → in-progress → review`; both `last_updated` (line 2 comment + line 38 key) bumped to `2026-05-12` and kept in sync per the hand-edited header convention established in Story 2.1. This story file's `Status:` field at line 3 flipped `ready-for-dev → in-progress → review` correspondingly. Epic 2 status untouched (remains `in-progress` per AC7 guidance).
- **Verification-path documentation** — `act`-driven AC3 was skipped because `act` rejects `${{ … }}` literal text inside action `inputs.<name>.description:` strings, which is an `act`-parser strictness issue not present on GitHub Actions itself. The action's description strings are canonical per the AC1 verbatim body and Story 2.3 will exercise the action via real GitHub Actions (and via additional `act` runs once the spec author and Story 2.3 collectively decide whether to keep or rephrase the expression-text in descriptions). Per the story's "surface both verification approaches" instruction, both attempted and the alternative is the authoritative pass.
- **Deferred items inherited from Story 2.1 (out of scope here; surfaced for hand-off)** — (i) bucket+key state-collision risk between the two trees (`deferred-work.md:61`) — Story 2.3 territory; (ii) two-tree drift CI guard (`deferred-work.md:63`) — out of scope, will be naturally addressed alongside Story 2.3/2.4 rewires; (iii) `required_version` toolchain pin gap (`deferred-work.md:62`) — out of scope.
- **Hand-off to Story 2.3** — the new `./.github/actions/init-terraform` action is ready for one-line `uses:` swaps at the two known call sites: `.github/workflows/onboard-konnect-teams.yaml:116-124` (outer tree, env-driven `AWS_S3_BUCKET`/`AWS_REGION`, currently `-backend-config=config.s3.tfbackend` + dynamic `bucket`/`key`/`region` overrides) and `.github/actions/provision-konnect-resources/action.yaml:109-116` (inner tree, input-templated bucket `kw.konnect.team.resources.${{ inputs.konnect-team-name }}`, currently `-backend-config=config.s3.tfbackend` + dynamic overrides). **Open design question for Story 2.3** (not new; restated for visibility): the action accepts a single `backend-config-path` input and Story 2.3 must decide how to plumb the dynamic `bucket`/`region`/`key` overrides — three candidates per Dev Notes "What this story does NOT do": (a) add an optional `backend-config-overrides` multiline input to this action (additive, non-breaking), (b) keep dynamic overrides at the caller via a follow-up step that re-runs `terraform init -backend-config="bucket=…"`, or (c) hardcode per-team bucket into `config.s3.tfbackend`. The story-2.2 scope did not require resolving this; it is Story 2.3's first decision.

### File List

- `.github/actions/init-terraform/action.yml` — new (AC1)
- `.github/actions/init-terraform/README.md` — new (AC2)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — modified (key flip + `last_updated` bump; header comment kept in sync)
- `_bmad-output/implementation-artifacts/2-2-create-shared-init-terraform-composite-action.md` — modified (Status flip, tasks/subtasks checked, Dev Agent Record populated)
