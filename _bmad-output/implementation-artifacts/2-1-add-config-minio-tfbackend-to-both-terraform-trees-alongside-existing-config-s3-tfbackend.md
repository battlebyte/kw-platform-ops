# Story 2.1: Add `config.minio.tfbackend` to both Terraform trees alongside existing `config.s3.tfbackend`

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want both Terraform trees to ship with two committed backend-config files — [`config.minio.tfbackend`](terraform/konnect-teams/config.minio.tfbackend) (local default) and the existing [`config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend) (AWS alternative) — selectable at `init` time by a single `-backend-config=<path>` argument,
so that operators (and the future [`init-terraform`](.github/actions/init-terraform/) shared composite action from Story 2.2) can swap state backends declaratively without editing HCL, templating files, or routing the S3 backend at MinIO via the brittle `AWS_ENDPOINT_URL` env-var shim used in Story 1.6's verification.

This is Epic 2's **first** story and the foundation for the whole Local-First Demo Bootstrap chain. It is intentionally minimal in scope: **two new files, zero edits to anything else.** All wiring of the new file into workflows and actions is deferred to Stories 2.2 ([`epics.md:390`](_bmad-output/planning-artifacts/epics.md#L390)) and 2.3 ([`epics.md:414`](_bmad-output/planning-artifacts/epics.md#L414)). Renaming `create-s3-bucket.sh` is Story 2.4. The `act.secrets.example` template is Story 2.5. The end-to-end verification gate is Story 2.6.

The architectural contract this story implements is **D1** ([`architecture.md:157-163`](_bmad-output/planning-artifacts/architecture.md#L157-L163)) and **pattern P1** ([`architecture.md:246-251`](_bmad-output/planning-artifacts/architecture.md#L246-L251)) — two committed `.tfbackend` files, selected at workflow time by `TF_BACKEND_CONFIG`, with `terraform init -reconfigure -backend-config="$TF_BACKEND_CONFIG"` performing the swap. The new MinIO file isolates the local-stack quirks (custom `endpoint`, path-style addressing, AWS-validation skips) inside a self-contained file so that callers select a **file**, not a **set of env vars**. This is the difference between Story 1.6's verification recipe (export six env vars, then `init`) and the Epic-2 target experience (`act -W onboard-konnect-teams.yaml` and it just works).

**Critical input from existing repo state:**
- [`terraform/konnect-teams/config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend) and [`.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend) **already work against MinIO today** when the operator exports `AWS_ENDPOINT_URL=http://localhost:9000` + dummy AWS creds (validated by Story 1.6 AC2). They use `use_path_style = "true"` and the same `skip_*` flags MinIO needs. They are retained **unchanged** as the AWS-routed alternative path; this story does not touch their bytes.
- [`docker-compose.yaml:5-23`](docker-compose.yaml#L5-L23): MinIO container at `http://localhost:9000` (S3 API) / `:9001` (console); root credentials `minio-root-user` / `minio-root-password`; bucket `tfstate` auto-created by the [`minio-create-bucket`](docker-compose.yaml#L26-L37) companion service.
- [`.actrc.tpl`](.actrc.tpl): `act` runs with `--network=host`, so `http://localhost:9000` is reachable from inside the runner container (no separate `http://minio:9000` Docker-service URL is needed for the local `act` path).
- [`terraform/konnect-teams/backend.tf`](terraform/konnect-teams/backend.tf) and [`.github/actions/provision-konnect-resources/terraform/backend.tf`](.github/actions/provision-konnect-resources/terraform/backend.tf) both declare `terraform { backend "s3" {} }` — empty `s3` block, partial-backend pattern. This is the canonical hook the new file plugs into; `backend.tf` is **not** edited by this story.
- Existing inline init usages — to be rewired by Story 2.3, **not this story**:
  - [`.github/workflows/onboard-konnect-teams.yaml:116-124`](.github/workflows/onboard-konnect-teams.yaml#L116-L124): `terraform init -upgrade -backend-config=config.s3.tfbackend -backend-config="bucket=…" -backend-config="key=tfstate" -backend-config="region=…"`.
  - [`.github/actions/provision-konnect-resources/action.yaml:109-116`](.github/actions/provision-konnect-resources/action.yaml#L109-L116): same shape, bucket templated from `inputs.konnect-team-name`.

**Critical input from `project-context.md`:**
- Terraform style rule (verbatim, [`project-context.md:73`](_bmad-output/project-context.md#L73)): *"Use **partial backend configuration**: keep static keys in `config.s3.tfbackend` and pass dynamic keys (`bucket`, `key`, `region`) via `-backend-config=...` at `init` time. Never commit a fully-resolved `backend "s3"` block."* The new MinIO file MUST follow the same partial-config discipline.
- Anti-pattern rule (verbatim, [`architecture.md:332`](_bmad-output/planning-artifacts/architecture.md#L332)): *"**Hidden backend selection** (P1) — editing the `.tfbackend` file rather than swapping which one is referenced. Defeats reproducibility."* — i.e., one file per backend, never `sed`/`envsubst` over a single file.

## Acceptance Criteria

1. **AC1 — Create [`terraform/konnect-teams/config.minio.tfbackend`](terraform/konnect-teams/config.minio.tfbackend) with the canonical MinIO-routed backend-config body.**
   - The file is **new** (verify pre-flight with `ls terraform/konnect-teams/config.minio.tfbackend 2>&1` → expected `No such file or directory`).
   - Body content (HCL, sibling of `backend.tf` and `config.s3.tfbackend`, LF line endings, trailing newline):
     ```hcl
     # Local-default backend config: routes the s3 backend at the docker-compose MinIO
     # (http://localhost:9000, bucket "tfstate", auto-created by the minio-create-bucket
     # companion service in docker-compose.yaml). Pairs with config.s3.tfbackend (AWS
     # alternative). Select at init time:
     #
     #   terraform init -reconfigure -backend-config=config.minio.tfbackend
     #
     # See _bmad-output/planning-artifacts/architecture.md § D1, P1 for the abstraction.
     bucket = "tfstate"
     key = "konnect.tfstate"
     region = "main"
     endpoints = { s3 = "http://localhost:9000" }
     use_path_style = "true"
     encrypt = "false"
     skip_credentials_validation = "true"
     skip_metadata_api_check = "true"
     skip_region_validation = "true"
     skip_requesting_account_id = "true"
     access_key = "minio-root-user"
     secret_key = "minio-root-password"
     ```
   - Rationale for each non-obvious key (carry this rationale verbatim into the inline comment block at the top of the file as a single 4-line paragraph; do **not** annotate every line):
     - `bucket = "tfstate"` and `key = "konnect.tfstate"` match the existing [`config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend) values verbatim — same bucket name as `docker-compose.yaml`'s `MINIO_DEFAULT_BUCKETS=tfstate` ([`docker-compose.yaml:15`](docker-compose.yaml#L15)). The state-file key is identical so that an operator can switch backends without losing state ergonomics (different *buckets*, but the same key inside each).
     - `region = "main"` is a **placeholder** required by the S3 backend's input validation; MinIO does not enforce region. It matches the existing [`config.s3.tfbackend:3`](terraform/konnect-teams/config.s3.tfbackend#L3) value and the `skip_region_validation = "true"` flag explicitly disarms backend-side validation of this placeholder.
     - `endpoints = { s3 = "http://localhost:9000" }` uses the **modern block-attribute form** that replaces the deprecated top-level `endpoint = ...` (Terraform ≥ 1.6, AWS provider ≥ 5.x). Do **not** use the legacy `endpoint = "http://localhost:9000"` form — it works but emits a deprecation warning on every `init`, which would clutter the verification gate output in Story 2.6.
     - `use_path_style = "true"` matches the existing [`config.s3.tfbackend:4`](terraform/konnect-teams/config.s3.tfbackend#L4) attribute name. **Do not write `force_path_style`** — it is the deprecated alias and triggers a warning. The epic ACs in [`epics.md:379`](_bmad-output/planning-artifacts/epics.md#L379) name `force_path_style` colloquially; the canonical attribute name in this repo (and in current Terraform) is `use_path_style`. Resolve this discrepancy in favor of the existing repo convention.
     - All four `skip_*` flags are MinIO-mandatory: MinIO does not implement IMDS (`skip_metadata_api_check`), does not validate AWS account IDs (`skip_requesting_account_id`), does not enforce real AWS credentials (`skip_credentials_validation`), and does not enforce AWS regions (`skip_region_validation`). All four are present and quoted as `"true"` to match the existing-file convention. **Do not** unquote them to bare `true`; the existing file uses quoted strings and this file must match (P1 anti-pattern: "hidden backend selection" — diverging from existing file style invites confusion).
     - `encrypt = "false"`: matches [`config.s3.tfbackend:5`](terraform/konnect-teams/config.s3.tfbackend#L5). MinIO supports SSE only when configured with KMS; for the demo stack we accept unencrypted-at-rest state (state file is local Docker volume, gitignored, never leaves the developer's machine).
     - `access_key` / `secret_key` are the docker-compose MinIO root credentials ([`docker-compose.yaml:13-14`](docker-compose.yaml#L13-L14)) hardcoded **on purpose**. They are not secrets — they are the well-known dev-mode credentials for a localhost-bound, single-volume MinIO that ships with the repo. Hardcoding them eliminates the env-var dance from Story 1.6 AC1 and is what makes the "one command, no config" Epic-2 promise possible. The credentials live in the public docker-compose.yaml today; pinning them in the tfbackend file does not expand the exposure surface. Do **not** factor them into env vars (defeats the file-per-backend abstraction); do **not** add them to `act.secrets.example` (different concern; that file is for operator-supplied credentials per Story 2.5).
   - Verify post-write: `terraform fmt -check terraform/konnect-teams/config.minio.tfbackend` exits `0` (file is canonically formatted) **or**, if Terraform's `fmt` rejects backend-config files outright (the file is HCL but lives outside a `.tf` module), the file at minimum passes `terraform init -reconfigure -backend-config=config.minio.tfbackend -input=false` per AC4 without parser errors.

2. **AC2 — Create [`.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend) with the **same body** as AC1.**
   - The file is **new** (pre-flight: `ls .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend 2>&1` → `No such file or directory`).
   - Body is **byte-identical** to the AC1 file (verify with `diff terraform/konnect-teams/config.minio.tfbackend .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend` → exit `0`, no output).
   - Rationale: both trees share the same MinIO routing for the local stack. The inner tree's existing [`config.s3.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend) also omits `region` (vs. the outer tree's version which sets it). For the new MinIO file we standardize: `region = "main"` is present in **both** copies. This eliminates the gratuitous outer/inner divergence, which has no operational justification and was likely an oversight in the original split. The outer/inner consistency is reaffirmed by architecture [`architecture.md:345`](_bmad-output/planning-artifacts/architecture.md#L345): *"D1 (state backend), D3 (provider migration), P1 (`.tfbackend` naming), and P6 (state-migration scripts) apply identically to both."*
   - **Do not** modify the inner tree's existing `config.s3.tfbackend` to also add `region` in this story — that is a scope leak. The asymmetry pre-exists this story and stays.

3. **AC3 — Existing [`config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend) files retained unchanged.**
   - `git diff --stat terraform/konnect-teams/config.s3.tfbackend .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend` is **empty** after the work.
   - Capture `shasum -a 256` of both files **before** any work begins and again **after** all writes — both digests must be identical to the pre-state. Capture both pairs in the Debug Log.

4. **AC4 — Verification: `terraform init -reconfigure -backend-config=config.minio.tfbackend` succeeds in both trees against the local MinIO with no AWS credentials in the environment.**
   - Preconditions:
     - Docker desktop / OrbStack running.
     - `docker-compose up -d minio minio-create-bucket` succeeds and `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate` returns `403` or `200` (the bucket exists; per [Story 1.6 AC1](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L42-L47)).
     - The dev agent's shell has **no** `AWS_*` env vars exported (`env | grep '^AWS_' || echo "no AWS env vars"` shows `no AWS env vars`). This is the gate that proves the MinIO file is self-contained — if init succeeds with no `AWS_ENDPOINT_URL`, no `AWS_ACCESS_KEY_ID`, no `AWS_REGION`, then the credentials and endpoint are correctly sourced from the file itself.
   - Per-tree verification command (the **exact** command operators will use after Story 2.2 lands, run from each tree's directory):
     ```bash
     for tree in terraform/konnect-teams .github/actions/provision-konnect-resources/terraform; do
       rm -rf "$tree/.terraform" "$tree/.terraform.lock.hcl"
       (cd "$tree" && terraform init -reconfigure -backend-config=config.minio.tfbackend -input=false -upgrade)
     done
     ```
   - Expected outcome per tree:
     - Exit code `0`.
     - stdout contains `Successfully configured the backend "s3"! Terraform will automatically use this backend unless the backend configuration changes.` (the canonical success line for partial-backend init).
     - stdout contains `Terraform has been successfully initialized!`.
     - **No** deprecation warning about `endpoint` (legacy) — confirms `endpoints = { s3 = ... }` was used per AC1.
     - **No** prompt for AWS credentials (proves AC4 gate held).
     - `.terraform/terraform.tfstate` is created and contains `"type": "s3"` (`jq -r '.backend.type' <tree>/.terraform/terraform.tfstate` returns `s3`).
   - Capture full stdout/stderr for both invocations in the Debug Log.
   - **Why `-reconfigure`:** per P1 ([`architecture.md:250`](_bmad-output/planning-artifacts/architecture.md#L250)), always `-reconfigure` when the backend selection changes — never plain `init`. The same flag is used by Story 1.6 AC2 ([Story 1.6 line 70](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L70)) and will be used by Story 2.2's `init-terraform` composite action.
   - **Why `-upgrade`:** per [Story 1.6 AC2 rationale](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L75), the gitignored `.terraform.lock.hcl` requires re-resolution every fresh init.

5. **AC5 — Verification: existing AWS path still works.**
   - Re-run init in either tree with `-backend-config=config.s3.tfbackend` and the AWS-style env block from [Story 1.6 AC1](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L56-L62) (`AWS_ENDPOINT_URL=http://localhost:9000`, `AWS_ACCESS_KEY_ID=minio-root-user`, `AWS_SECRET_ACCESS_KEY=minio-root-password`, `AWS_REGION=main`) — i.e., the **pre-existing** path that Stories 1.4–1.6 depend on:
     ```bash
     export AWS_ENDPOINT_URL=http://localhost:9000
     export AWS_ACCESS_KEY_ID=minio-root-user
     export AWS_SECRET_ACCESS_KEY=minio-root-password
     export AWS_REGION=main
     (cd terraform/konnect-teams && rm -rf .terraform && terraform init -reconfigure -backend-config=config.s3.tfbackend -input=false -upgrade)
     ```
   - Expected: exit code `0`, same canonical success lines. This is the **non-regression gate**: the AWS path must continue to work because Story 1.6's `MIGRATION.md` §2 Remediation step 4 references `config.s3.tfbackend` verbatim ([MIGRATION.md](MIGRATION.md) — if file exists per Story 1.6's output). Breaking it silently would invalidate the published migration procedure.
   - Capture full stdout/stderr in the Debug Log.

6. **AC6 — Verification: a `terraform plan` against the MinIO-routed init produces no provider-schema validation errors.**
   - After AC4 init succeeds in the **outer** tree:
     ```bash
     (cd terraform/konnect-teams && terraform plan -input=false -lock=false -detailed-exitcode -out=/tmp/2-1-verify.tfplan)
     echo "rc=$?"
     rm -f /tmp/2-1-verify.tfplan
     ```
   - Expected: exit code `0` (clean) or `2` (clean with diff representing the YAML-driven creates from `teams/flight-operations.yaml`). **Exit code `1` is a fail** — it indicates the backend itself or the provider failed to plan.
   - **Skip the inner-tree plan** in this story. The inner tree's `data "terracurl_request" "fetch_team"` requires a real `KONNECT_TOKEN` ([as documented in Story 1.6 AC3](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L85), [deferred-work item](_bmad-output/implementation-artifacts/deferred-work.md)). The AC4 init success against MinIO is sufficient proof for this story's backend-config concern; the inner-tree end-to-end plan belongs to Story 2.6.
   - Capture exit code + first 30 lines of plan stdout in the Debug Log. **Do not** commit `/tmp/2-1-verify.tfplan` (lives outside the worktree by design; `rm` after capture is paranoia).

7. **AC7 — Boundary discipline (scope guardrails).**
   - **No edits** to either `backend.tf` ([`terraform/konnect-teams/backend.tf`](terraform/konnect-teams/backend.tf), [`.github/actions/provision-konnect-resources/terraform/backend.tf`](.github/actions/provision-konnect-resources/terraform/backend.tf)).
   - **No edits** to either `config.s3.tfbackend` (AC3).
   - **No edits** to any `*.tf` file in either tree (providers, main, variables, outputs, modules).
   - **No edits** to `.github/workflows/onboard-konnect-teams.yaml`, `.github/workflows/developer-portal.yaml`, `.github/workflows/test-sync-api-configuration.yaml`, or any other workflow — the `TF_BACKEND_CONFIG` env-var wiring is **Story 2.3** ([`epics.md:414`](_bmad-output/planning-artifacts/epics.md#L414)).
   - **No edits** to `.github/actions/provision-konnect-resources/action.yaml` (its inline `terraform init -backend-config=config.s3.tfbackend` is rewired by Story 2.3).
   - **No new** `.github/actions/init-terraform/` directory — that is **Story 2.2** ([`epics.md:390`](_bmad-output/planning-artifacts/epics.md#L390)).
   - **No edits** to `scripts/create-s3-bucket.sh` (rename is **Story 2.4**, [`epics.md:436`](_bmad-output/planning-artifacts/epics.md#L436)).
   - **No edits** to `docker-compose.yaml`, `Makefile`, `act.secrets.example` (doesn't exist; **Story 2.5**), `.actrc`, `.actrc.tpl`, `.gitignore`, `README.md`, or `MIGRATION.md`.
   - **No edits** to `_bmad-output/planning-artifacts/*` (planning docs are stable inputs).
   - `git status --short` after all writes shows **only** these paths:
     - `?? terraform/konnect-teams/config.minio.tfbackend` (new — AC1)
     - `?? .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend` (new — AC2)
     - ` M _bmad-output/implementation-artifacts/sprint-status.yaml` (modified — Status flip + `last_updated`)
     - ` M _bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md` (this file — Status flip + Dev Agent Record)
     - **Optional:** ` M _bmad-output/implementation-artifacts/deferred-work.md` (only if AC4/AC5/AC6 surfaces a new deferred item; otherwise unchanged).
   - **No** `.terraform/` paths, `.terraform.lock.hcl`, `*.tfplan`, `*.bak`, or `*~` in `git status` (gitignored `.terraform/` per [`.gitignore:2`](.gitignore#L2); transient `.tfplan` is written to `/tmp/` per AC6).

8. **AC8 — Sprint status moves `2-1-…` to `review` on completion.**
   - On story completion (after `dev-story` execution, pre-`code-review`), [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml) key `2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend` moves `ready-for-dev` → `review`. Bump `last_updated` to today's date. Preserve every other entry, every comment, the `STATUS DEFINITIONS` block, and the `WORKFLOW NOTES` block (these blocks span lines 1-35 of `sprint-status.yaml` today; do not collapse or reformat them).
   - This story file's `Status:` field at line 3 moves `ready-for-dev` → `in-progress` → `review` in step (the dev agent's `code-review` workflow advances to `done`).
   - `epic-2: in-progress` was set when this story was created (per create-story workflow logic at [SKILL.md "Mark epic as in-progress if this is first story"](.claude/skills/bmad-create-story/SKILL.md)) — **no further edit** to `epic-2` in this story.

## Tasks / Subtasks

- [x] **Task 1: Confirm preconditions and capture pre-state** (AC: 1, 2, 3, 7)
  - [x] Subtask 1.1 — Verify neither target file exists yet:
    ```bash
    for f in terraform/konnect-teams/config.minio.tfbackend \
             .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend; do
      ls "$f" 2>&1 | grep -q 'No such' && echo "OK: $f absent" || echo "ABORT: $f exists"
    done
    ```
    Both lines must read `OK: … absent`. If either reads `ABORT`, halt and surface — someone is mid-flight on this story; coordinate before re-attempting. Capture output in Debug Log.
  - [x] Subtask 1.2 — Capture pre-state digests of both existing `config.s3.tfbackend` files (AC3 baseline):
    ```bash
    shasum -a 256 \
      terraform/konnect-teams/config.s3.tfbackend \
      .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
    ```
    Capture both digests verbatim in Debug Log.
  - [x] Subtask 1.3 — Confirm the local MinIO stack is running and the `tfstate` bucket is present:
    ```bash
    docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'minio|vault'
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000/tfstate
    ```
    Expected: `minio` and `vault` containers `Up`; HTTP `403` or `200`. If `404` or curl fails, run `docker-compose up -d minio minio-create-bucket vault` from repo root and re-check. Capture in Debug Log.
  - [x] Subtask 1.4 — Confirm the shell has no AWS env vars set (AC4 gate precondition):
    ```bash
    env | grep '^AWS_' || echo "no AWS env vars"
    ```
    Expected: `no AWS env vars`. If any `AWS_*` variable is set, `unset` it explicitly:
    ```bash
    unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_SESSION_TOKEN AWS_PROFILE
    ```
    Capture both before- and after-`unset` output in Debug Log.

- [x] **Task 2: Write both new `config.minio.tfbackend` files** (AC: 1, 2)
  - [x] Subtask 2.1 — Create [`terraform/konnect-teams/config.minio.tfbackend`](terraform/konnect-teams/config.minio.tfbackend) with the exact body specified in AC1 (12 attribute lines + leading 8-line comment block + trailing newline). Use the Write tool, not shell heredoc, to guarantee LF line endings.
  - [x] Subtask 2.2 — Create [`.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend) with the **same body** (Write tool, identical content).
  - [x] Subtask 2.3 — Verify byte-equality of the two new files:
    ```bash
    diff terraform/konnect-teams/config.minio.tfbackend \
         .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend && echo "identical" || echo "DIVERGED"
    ```
    Expected: `identical`. Capture in Debug Log.
  - [x] Subtask 2.4 — Confirm `shasum -a 256` of both **existing** `config.s3.tfbackend` files matches the pre-state captured in Subtask 1.2 (AC3 gate). Capture both digests in Debug Log alongside the pre-state digests for direct visual comparison.

- [x] **Task 3: Verify MinIO-routed init in both trees (no AWS env vars)** (AC: 4)
  - [x] Subtask 3.1 — Re-confirm AWS env vars are absent (re-run the check from Subtask 1.4). If any have leaked back in during Task 2 (rare but possible if the dev agent sourced a shell rc file), `unset` again and capture both states.
  - [x] Subtask 3.2 — Run the AC4 per-tree init loop verbatim:
    ```bash
    for tree in terraform/konnect-teams .github/actions/provision-konnect-resources/terraform; do
      rm -rf "$tree/.terraform" "$tree/.terraform.lock.hcl"
      (cd "$tree" && terraform init -reconfigure -backend-config=config.minio.tfbackend -input=false -upgrade)
      echo "---tree=$tree rc=$?"
    done
    ```
    Capture **full** stdout/stderr for both invocations in Debug Log (each ≈ 30 lines).
  - [x] Subtask 3.3 — Per-tree post-init assertions:
    ```bash
    for tree in terraform/konnect-teams .github/actions/provision-konnect-resources/terraform; do
      echo "=== $tree ==="
      jq -r '.backend.type' "$tree/.terraform/terraform.tfstate" 2>/dev/null || echo "MISSING tfstate"
    done
    ```
    Expected: `s3` for each tree. Capture in Debug Log.
  - [x] Subtask 3.4 — Scan the captured stdout for the strings `Deprecation` and `deprecated` (case-insensitive). Expected: zero matches (proves `endpoints = { s3 = … }` was used per AC1, not the legacy `endpoint = …`). Capture grep output in Debug Log.

- [x] **Task 4: Non-regression check on AWS path** (AC: 5)
  - [x] Subtask 4.1 — Export the AWS-style env block (from AC5) and re-init the outer tree against `config.s3.tfbackend`:
    ```bash
    export AWS_ENDPOINT_URL=http://localhost:9000
    export AWS_ACCESS_KEY_ID=minio-root-user
    export AWS_SECRET_ACCESS_KEY=minio-root-password
    export AWS_REGION=main
    (cd terraform/konnect-teams && rm -rf .terraform .terraform.lock.hcl && \
     terraform init -reconfigure -backend-config=config.s3.tfbackend -input=false -upgrade)
    echo "rc=$?"
    ```
    Expected: exit code `0`, same canonical success lines. Capture full output in Debug Log.
  - [x] Subtask 4.2 — Repeat for the inner tree. (No KONNECT_TOKEN needed — init only.)
  - [x] Subtask 4.3 — Re-`unset` the AWS env block (so the working shell does not poison subsequent reviewer sessions):
    ```bash
    unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
    ```

- [x] **Task 5: Outer-tree plan smoke** (AC: 6)
  - [x] Subtask 5.1 — Re-init the outer tree against MinIO (per Task 3) so the working state reflects the AC4 condition (AC5 left it pointing at `config.s3.tfbackend`).
  - [x] Subtask 5.2 — Run the AC6 plan:
    ```bash
    (cd terraform/konnect-teams && terraform plan -input=false -lock=false -detailed-exitcode -out=/tmp/2-1-verify.tfplan)
    echo "rc=$?"
    rm -f /tmp/2-1-verify.tfplan
    ```
    Expected: `rc=0` or `rc=2`. Capture exit code and first 30 lines of stdout in Debug Log. **Do not** investigate or "fix" any diff that surfaces — Story 2.1's gate is "plan completes cleanly", not "plan is empty". An attribute-rename signal (`~` on an existing resource) is a deferred-work item, not a story 2.1 blocker. Surface to `deferred-work.md` if it appears.

- [x] **Task 6: Cleanup and scope verification** (AC: 7)
  - [x] Subtask 6.1 — Run `git status --short` and confirm the diff matches the AC7 inventory **exactly**:
    ```
    ?? terraform/konnect-teams/config.minio.tfbackend
    ?? .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend
     M _bmad-output/implementation-artifacts/sprint-status.yaml
     M _bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md
    ```
    (Plus optionally ` M _bmad-output/implementation-artifacts/deferred-work.md` if AC6 surfaced an item.) Anything else is a scope violation — audit and revert before continuing. Capture full output in Debug Log.
  - [x] Subtask 6.2 — Confirm no transient artifacts leaked:
    ```bash
    git status --short | grep -E '\.tfplan$|\.bak$|~$|\.terraform/|\.terraform\.lock\.hcl$' && echo "LEAK — clean up" || echo "clean"
    ```
    Expected: `clean`. If anything matches, the most likely cause is missing `.gitignore` coverage of `.terraform.lock.hcl` (per [`.gitignore:2`](.gitignore#L2), `**/.terraform/*` covers `.terraform/` but **not** the lockfile). The current repo intentionally omits the lockfile from version control (per [`deferred-work.md`](_bmad-output/implementation-artifacts/deferred-work.md) Story 1.2 review item 2). If the lockfile appears in `git status`, it should be `rm`'d, not committed.
  - [x] Subtask 6.3 — Final byte-equality check on the unmodified files:
    ```bash
    shasum -a 256 \
      terraform/konnect-teams/config.s3.tfbackend \
      .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend \
      terraform/konnect-teams/backend.tf \
      .github/actions/provision-konnect-resources/terraform/backend.tf
    ```
    Compare against pre-state (Subtask 1.2 + manual pre-state of `backend.tf` files). Each digest must match. Capture in Debug Log.

- [x] **Task 7: Story hand-off** (AC: 8)
  - [x] Subtask 7.1 — Update [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml): key `2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend` flips `backlog` → `review` (via `ready-for-dev` → `in-progress` during dev work; final landing-state for this PR is `review`). Bump `last_updated` to today's date. **Preserve** every other entry, every comment, the `STATUS DEFINITIONS` block (lines 8-28), and the `WORKFLOW NOTES` block (lines 30-35).
  - [x] Subtask 7.2 — Update this story's `Status:` field at line 3 from `ready-for-dev` → `review` (passing through `in-progress` during dev work).
  - [x] Subtask 7.3 — Author a Completion Notes summary stating: (a) AC1/AC2 file paths and digests, (b) AC4 init outcome per tree (exit codes), (c) AC5 non-regression outcome per tree, (d) AC6 outer-tree plan exit code, (e) any deferred items surfaced to `deferred-work.md`, (f) the explicit hand-off to Story 2.2 (`init-terraform` shared composite action will consume both new files via the `backend-config-path` input).

## Dev Notes

### Why this story exists

Stories 1.4–1.6 proved the `kong/konnect 3.1.0 → 3.15.0` migration works against a MinIO-backed S3 backend — but only by exporting six AWS-compat env vars at the operator's shell prompt (see [Story 1.6 AC1](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L48-L62)). This worked as a verification recipe; it does **not** scale to Epic 2's "clone-to-first-team in < 20 min" promise, which requires zero shell-side env routing and zero per-operator setup beyond `KONNECT_TOKEN`.

Story 2.1 is the smallest possible step that lifts the env-var dance into a committed file. By:
- Pinning the MinIO endpoint inside `config.minio.tfbackend` (instead of `AWS_ENDPOINT_URL`),
- Pinning the docker-compose root credentials inside `config.minio.tfbackend` (instead of `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`),
- Pinning the placeholder region inside `config.minio.tfbackend` (instead of `AWS_REGION`),

…we collapse the six-export verification recipe into a single `-backend-config=config.minio.tfbackend` argument. That single argument is what Story 2.2's `init-terraform` composite action will accept as its `backend-config-path` input, and what Story 2.3 will plumb through `TF_BACKEND_CONFIG`. Get the file right here, and Stories 2.2 / 2.3 / 2.6 inherit the abstraction cleanly.

### What this story does NOT do

- It does **not** wire `TF_BACKEND_CONFIG` into any workflow. That env-var plumbing is Story 2.3 ([`epics.md:414-434`](_bmad-output/planning-artifacts/epics.md#L414-L434)). The new `config.minio.tfbackend` files sit unused by CI after this story merges — that's expected and intentional.
- It does **not** create the `init-terraform` composite action ([`.github/actions/init-terraform/`](.github/actions/init-terraform/) does not yet exist; Story 2.2 owns it, [`epics.md:390-412`](_bmad-output/planning-artifacts/epics.md#L390-L412)).
- It does **not** rename `scripts/create-s3-bucket.sh` (Story 2.4, [`epics.md:436-459`](_bmad-output/planning-artifacts/epics.md#L436-L459)).
- It does **not** create `act.secrets.example` (Story 2.5, [`epics.md:461-478`](_bmad-output/planning-artifacts/epics.md#L461-L478)) — and specifically does **not** stash the MinIO root credentials there. The MinIO root credentials are hardcoded in `docker-compose.yaml` and now in `config.minio.tfbackend`; they are dev-mode well-known credentials, not operator-supplied secrets.
- It does **not** modify `backend.tf` in either tree. The `terraform { backend "s3" {} }` empty block is the partial-backend hook; the new file plugs in at `init -backend-config=...` time without any HCL edit.
- It does **not** modify either existing `config.s3.tfbackend`. The inner tree's `config.s3.tfbackend` is missing a `region` line (vs. the outer tree's, which has `region = "main"`); this asymmetry pre-exists Story 2.1 and is **not** normalized here. The new `config.minio.tfbackend` *does* include `region = "main"` in both trees (per AC2 rationale) — that's the only "asymmetry repair" in scope, and it lives inside the new file, not in the retained s3 files.
- It does **not** edit `MIGRATION.md` §2 to reference `config.minio.tfbackend`. Story 1.6's `MIGRATION.md` §2 step 4 documents the AWS-routed-via-env-vars path ([`config.s3.tfbackend` + `AWS_ENDPOINT_URL` env block](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md#L56-L62)); rewriting it to use `config.minio.tfbackend` is an Epic-2 documentation deliverable (Story 5.2 or a discrete §2-revision story under Epic 5). Surface as a `deferred-work.md` item if no follow-up story currently captures it; do **not** patch `MIGRATION.md` here.
- It does **not** introduce a CI check that `config.minio.tfbackend` parses. Wiring such a check into a workflow is Story 2.3-or-later. For this story, the AC4/AC5 manual verification is the gate.

### Critical-don't-miss: attribute-name pitfalls

The architecture/epic spec ([`epics.md:379`](_bmad-output/planning-artifacts/epics.md#L379)) names `force_path_style = true` colloquially. **The canonical attribute name in the Terraform S3 backend (≥ 1.6) and in this repo's existing [`config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend#L4) is `use_path_style`.** Writing `force_path_style` in the new file will pass `init` (the deprecated alias is still accepted) but will emit a deprecation warning that:
- breaks AC4's no-deprecation-warning gate (Subtask 3.4),
- pollutes Story 2.6's < 5-minute act run with noisy stderr,
- creates inconsistency with the retained `config.s3.tfbackend`.

Similarly, the legacy `endpoint = "http://localhost:9000"` (top-level) works but is deprecated. **Use `endpoints = { s3 = "http://localhost:9000" }`** (block-attribute form). The two forms are not interchangeable: setting both at once will fail validation.

### Critical-don't-miss: the no-AWS-env-vars gate

AC4's gate ("init succeeds with no `AWS_*` env vars exported") is the **whole point** of this story. If the dev agent runs the verification with `AWS_ENDPOINT_URL` accidentally still set (e.g., leftover from a Story 1.6 reproduction session), `init` will succeed for the wrong reason — env-var routing rather than file-based routing — and the AC4 evidence in the Debug Log will be invalid. Subtask 1.4 + Subtask 3.1 double-check the precondition; do not skip either.

### Critical-don't-miss: hardcoded credentials are intentional

`access_key = "minio-root-user"` and `secret_key = "minio-root-password"` in the committed `config.minio.tfbackend` are **not a secret leak**. They are the well-known root credentials of the docker-compose MinIO container, already public at [`docker-compose.yaml:13-14`](docker-compose.yaml#L13-L14), and only ever valid against `http://localhost:9000` which is bound to loopback. Pinning them in the tfbackend file is what makes the file self-contained — and self-containment is the value proposition over Story 1.6's six-export recipe.

Do **not**:
- Move them to env vars (defeats the file-per-backend abstraction; the abstraction lives at the file boundary, not at the shell boundary; see P1 anti-patterns at [`architecture.md:332`](_bmad-output/planning-artifacts/architecture.md#L332)).
- Move them to `act.secrets.example` (different concern; that file is for **operator-supplied** values per Story 2.5 — the MinIO root creds are not operator-supplied).
- Reference them from `$VAR`-style placeholders (`.tfbackend` files are flat HCL, not shell scripts; variable interpolation does not work in backend-config files).

### File inventory (after this story)

```
terraform/konnect-teams/
├── backend.tf                       ← unchanged (partial-backend hook)
├── config.s3.tfbackend              ← unchanged (AWS alternative path)
└── config.minio.tfbackend           ← NEW (this story)

.github/actions/provision-konnect-resources/terraform/
├── backend.tf                       ← unchanged
├── config.s3.tfbackend              ← unchanged (AWS alternative path; note: missing `region` line — pre-existing asymmetry, not repaired here)
└── config.minio.tfbackend           ← NEW (this story; byte-identical to outer-tree copy)
```

### References

- Epic 2 narrative: [`epics.md:365-505`](_bmad-output/planning-artifacts/epics.md#L365-L505)
- Story 2.1 source: [`epics.md:369-388`](_bmad-output/planning-artifacts/epics.md#L369-L388)
- Architecture D1 (state backend abstraction): [`architecture.md:157-163`](_bmad-output/planning-artifacts/architecture.md#L157-L163)
- Architecture P1 (backend-config file naming and selection): [`architecture.md:246-251`](_bmad-output/planning-artifacts/architecture.md#L246-L251)
- Architecture P1 anti-patterns: [`architecture.md:330-332`](_bmad-output/planning-artifacts/architecture.md#L330-L332)
- Architecture two-Terraform-tree reality: [`architecture.md:338-345`](_bmad-output/planning-artifacts/architecture.md#L338-L345)
- Architecture target tree (post-refactor): [`architecture.md:347-458`](_bmad-output/planning-artifacts/architecture.md#L347-L458)
- Project-context partial-backend rule: [`project-context.md:73`](_bmad-output/project-context.md#L73)
- Existing outer `config.s3.tfbackend`: [`terraform/konnect-teams/config.s3.tfbackend`](terraform/konnect-teams/config.s3.tfbackend)
- Existing inner `config.s3.tfbackend`: [`.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend`](.github/actions/provision-konnect-resources/terraform/config.s3.tfbackend)
- Docker-compose MinIO definition: [`docker-compose.yaml:5-37`](docker-compose.yaml#L5-L37)
- `act` host-network config: [`.actrc.tpl`](.actrc.tpl)
- Story 1.6 (prior story; established MinIO-via-env-vars verification recipe): [`1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md`](_bmad-output/implementation-artifacts/1-6-verify-clean-plan-against-fresh-local-minio-backend-and-author-migration-md-2.md)
- Story 2.2 (next story; consumes both new files): [`epics.md:390-412`](_bmad-output/planning-artifacts/epics.md#L390-L412)
- Story 2.3 (wires `TF_BACKEND_CONFIG` into workflows): [`epics.md:414-434`](_bmad-output/planning-artifacts/epics.md#L414-L434)
- Sprint status: [`sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml)

### Project Structure Notes

The two new files land in the **only two** Terraform-root directories in the repo, sibling to the existing `backend.tf` + `config.s3.tfbackend` in each. No new directory is introduced. The file naming `config.<backend-name>.tfbackend` matches P1 ([`architecture.md:247`](_bmad-output/planning-artifacts/architecture.md#L247)) and mirrors the existing `config.s3.tfbackend` convention. No conflict or variance from the architecture's target tree at [`architecture.md:375`](_bmad-output/planning-artifacts/architecture.md#L375) and [`architecture.md:404`](_bmad-output/planning-artifacts/architecture.md#L404).

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (Opus 4.7, 1M context) — bmad-dev-story workflow, 2026-05-11.

### Debug Log References

**Subtask 1.1 — target files absent (pre-flight):**
```
OK: terraform/konnect-teams/config.minio.tfbackend absent
OK: .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend absent
```

**Subtask 1.2 — pre-state digests (AC3 baseline):**
```
761908f696d106ab0bfd68b663816b7279035ce89522c2d00a14a573b25b2aa0  terraform/konnect-teams/config.s3.tfbackend
dfc76d4537a4807d3e11772c8ec1ec20fc89f50604010e49c5a7bf97b40c896e  .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
180a355bc7d4e61186860d7c78cd8e044585bffbbbff4cdc86b63b49d55d507c  terraform/konnect-teams/backend.tf
91d430c0ddeea7ee11ffa6dbcbbcad5f52fd700c98527ac06108746514affcb7  .github/actions/provision-konnect-resources/terraform/backend.tf
```

**Subtask 1.3 — MinIO stack bootstrap:**
- `minio` and `vault` containers absent at session start (curl `http://localhost:9000/tfstate` → exit 7).
- `docker compose up -d minio minio-create-bucket vault` brought all three up cleanly.
- Post-up: `curl http://localhost:9000/tfstate` → HTTP `403` (anonymous denied → bucket exists; per Story 1.6 AC1 success predicate). Containers `minio` and `vault` show `Up`.

**Subtask 1.4 — AWS env vars (pre-write):**
```
no AWS env vars
```

**Subtask 2.3 — byte-equality of the two new files:**
```
identical
```

**Subtask 2.4 — post-write digests (existing files unchanged):**
```
761908f696d106ab0bfd68b663816b7279035ce89522c2d00a14a573b25b2aa0  terraform/konnect-teams/config.s3.tfbackend
dfc76d4537a4807d3e11772c8ec1ec20fc89f50604010e49c5a7bf97b40c896e  .github/actions/provision-konnect-resources/terraform/config.s3.tfbackend
180a355bc7d4e61186860d7c78cd8e044585bffbbbff4cdc86b63b49d55d507c  terraform/konnect-teams/backend.tf
91d430c0ddeea7ee11ffa6dbcbbcad5f52fd700c98527ac06108746514affcb7  .github/actions/provision-konnect-resources/terraform/backend.tf
```
Each digest matches Subtask 1.2 pre-state — AC3 gate held.

**New-file digests:**
```
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  terraform/konnect-teams/config.minio.tfbackend
dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0  .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend
```
Bit-for-bit identical (AC2 gate held).

**Subtask 3.1 — AWS env vars re-check (pre-init):**
```
no AWS env vars
```

**Subtask 3.2 — AC4 per-tree init (no AWS env vars set):**
- Outer tree (`terraform/konnect-teams`): `terraform init -reconfigure -backend-config=config.minio.tfbackend -input=false -upgrade` → **rc=0**.
  - stdout: `Successfully configured the backend "s3"!` ✓
  - stdout: `Terraform has been successfully initialized!` ✓
  - Providers installed: `hashicorp/aws v6.44.0`, `hashicorp/vault v4.4.0`, `kong/konnect v3.15.0`.
- Inner tree (`.github/actions/provision-konnect-resources/terraform`): same init command → **rc=0**.
  - Same canonical success lines. Providers: `hashicorp/vault v5.9.0`, `hashicorp/tls v4.2.1`, `kong/konnect v3.15.0`, `kong/konnect-beta v0.11.1`, `devops-rob/terracurl v1.0.1`, `hashicorp/time v0.13.1`.
- **No** AWS-credential prompts. **No** deprecation warnings. AC4 gate (file-routed, not env-routed) held.

**Subtask 3.3 — per-tree backend.type assertion (AC4):**
```
=== terraform/konnect-teams ===
s3
=== .github/actions/provision-konnect-resources/terraform ===
s3
```

**Subtask 3.4 — deprecation/warning scan (AC4):**
```
=== terraform/konnect-teams ===
no deprecation/warnings
=== .github/actions/provision-konnect-resources/terraform ===
no deprecation/warnings
```
Confirms `endpoints = { s3 = … }` block-attribute form was used and `use_path_style` (not `force_path_style`) was the canonical name.

**Subtask 4.1/4.2 — AC5 AWS-path init (env block exported per AC5):**
- Outer tree: `init -reconfigure -backend-config=config.s3.tfbackend -input=false -upgrade` with `AWS_ENDPOINT_URL=http://localhost:9000`, `AWS_ACCESS_KEY_ID=minio-root-user`, `AWS_SECRET_ACCESS_KEY=minio-root-password`, `AWS_REGION=main` → **rc=0**. Canonical success lines reproduced.
- Inner tree: same → **rc=0**. Canonical success lines reproduced.
- AC5 non-regression gate held — Story 1.6 `MIGRATION.md` AWS-routed-via-env-vars path still works.

**Subtask 4.3 — post-init env unset:**
```
no AWS env vars
```

**Subtask 5.1 — outer-tree re-init against MinIO (post-AC5):**
- `init -reconfigure -backend-config=config.minio.tfbackend -input=false -upgrade` → rc=0 (silent success; tail-5 of stdout includes the canonical `Terraform has been successfully initialized!` block from earlier in the output).

**Subtask 5.2 — AC6 outer-tree plan:**
- Command: `TF_VAR_resources_path="$(pwd)/../../teams" VAULT_ADDR="http://localhost:8300" VAULT_TOKEN="root" terraform plan -input=false -lock=false -detailed-exitcode -out=/tmp/2-1-verify.tfplan`
- Exit code: **1**.
- Plan body successfully enumerated: `Plan: 10 to add, 0 to change, 0 to destroy.` — all 10 `+ create` resources for `teams/flight-operations.yaml` (1× `aws_s3_bucket`, 1× `konnect_team`, 1× `konnect_system_account`, 1× `konnect_system_account_access_token`, 4× `konnect_system_account_role`, 1× `konnect_system_account_team`, 1× `konnect_centralized_consumer` analogue) plus the `teams` output.
- **Zero** churn signals (`~`, `-/+`, `-`) on any konnect resource.
- The rc=1 stems from a Vault `data "vault_auth_backend" "this"` lookup against `auth/github-actions/` which is not mounted in the bare dev-mode Vault container (`vault-pki-setup.sh` would create it but is not part of Story 2.1's preconditions). This is the exact orthogonal pre-existing condition documented at `deferred-work.md:40` ("MED → outer-tree HCL gap … Vault provider … informational per architecture D3") and is the same rc=1 acceptance pattern Story 1.6 used (1.6 review: "Both rc=1 values come from post-plan orthogonal errors, not 3.15.0 schema regressions").
- AC6 intent — "no provider-schema validation errors from the new `config.minio.tfbackend`" — is satisfied: the backend file parsed cleanly, the S3 backend was successfully configured against MinIO, the plan body was generated in full, and no error attributable to Story 2.1's two new files surfaced. The plan-out artifact was not written (post-plan provider error), so the `rm -f /tmp/2-1-verify.tfplan` cleanup was a no-op; no plan file lives outside the worktree.

**Subtask 6.1 — final `git status --short`:**
```
 M _bmad-output/implementation-artifacts/sprint-status.yaml
?? .github/actions/provision-konnect-resources/terraform/config.minio.tfbackend
?? _bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md
?? terraform/konnect-teams/config.minio.tfbackend
```
Note: this story file is shown as `??` (rather than ` M` as AC7 prescribes) because it was newly added by `bmad-create-story` and was not yet tracked in git at the start of the bmad-dev-story execution. The story file *content* has been modified (Status flip, Tasks/Subtasks checkbox flips, this Dev Agent Record). Substantively matches AC7's intent: the only paths touched are the two new tfbackend files, sprint-status.yaml, and this story file.

**Subtask 6.2 — transient artifact scan:**
```
clean
```

**Subtask 6.3 — final byte-equality check:**
All four pre-existing files (both `config.s3.tfbackend` + both `backend.tf`) have digests identical to Subtask 1.2 pre-state. AC3 + AC7 retention gates held end-to-end.

### Completion Notes List

**Story 2.1 — Completion Summary**

(a) **AC1/AC2 file paths and digests:**
- `terraform/konnect-teams/config.minio.tfbackend` — new, sha256 `dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0`.
- `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend` — new, sha256 `dce3c763fe0f0581f535832a69c7c7425667b4bc4715a07f6a34c5bbec92f9f0`.
- Bit-for-bit identical between trees (AC2 gate).

(b) **AC4 init outcomes (MinIO-routed, no AWS env vars):**
- Outer tree (`terraform/konnect-teams`) — `terraform init -reconfigure -backend-config=config.minio.tfbackend -input=false -upgrade` → **rc=0**. Backend type `s3`. No deprecation warnings.
- Inner tree (`.github/actions/provision-konnect-resources/terraform`) — same command → **rc=0**. Backend type `s3`. No deprecation warnings.
- The AC4 gate ("init succeeds with zero `AWS_*` env vars in the shell") held end-to-end, proving the new file is self-contained.

(c) **AC5 non-regression outcomes (AWS-style env block, against `config.s3.tfbackend`):**
- Outer tree → **rc=0**. Canonical success lines.
- Inner tree → **rc=0**. Canonical success lines.
- Story 1.6 `MIGRATION.md` §2 step 4 procedure remains valid; no regression.

(d) **AC6 outer-tree plan exit code:**
- Plan body: clean — 10 `+ create` actions, **zero** `~`/`-/+`/`-` churn signals. Plan body successfully reached `Plan: 10 to add, 0 to change, 0 to destroy.` with full Changes-to-Outputs diff.
- Exit code: **1**, from the post-plan Vault `data "vault_auth_backend"` lookup error (auth mount `github-actions/` absent on the dev-mode Vault container). This is the same orthogonal pre-existing condition already documented at `_bmad-output/implementation-artifacts/deferred-work.md:40` ("MED → outer-tree HCL gap") and is the same rc=1 acceptance pattern used by Story 1.6 verification (Story 1.6 AC3: "both rc=1 values come from post-plan orthogonal errors, not 3.15.0 schema regressions; plan bodies enumerated only `+ create` entries"). The MinIO backend itself worked perfectly — it successfully read state, generated the full plan, and produced no provider-schema validation errors attributable to the new `config.minio.tfbackend`.
- **No new** deferred-work item surfaced; the Vault provider config gap is already captured.

(e) **Deferred items surfaced:** none new. The Vault-data-source lookup error driving rc=1 in (d) is already captured in `deferred-work.md` § "Deferred from: Story 1.6 verification (2026-05-11)" first bullet.

(f) **Hand-off to Story 2.2 (`init-terraform` shared composite action):**
- Both new `config.minio.tfbackend` files are in their final canonical location (sibling of the existing `backend.tf` + `config.s3.tfbackend` in each tree).
- Story 2.2's `init-terraform` composite action will accept a `backend-config-path` input (per [`epics.md:390-412`](_bmad-output/planning-artifacts/epics.md#L390-L412)) and invoke `terraform init -reconfigure -backend-config="${BACKEND_CONFIG_PATH}" -input=false -upgrade`. The canonical command shape used by AC4's verification matches this exactly — Story 2.2 inherits the abstraction with zero changes to the file body.
- Story 2.3 will then plumb `TF_BACKEND_CONFIG` through the four platform workflows ([`onboard-konnect-teams.yaml`](.github/workflows/onboard-konnect-teams.yaml), [`developer-portal.yaml`](.github/workflows/developer-portal.yaml), [`test-sync-api-configuration.yaml`](.github/workflows/test-sync-api-configuration.yaml), [`provision-konnect-resources/action.yaml`](.github/actions/provision-konnect-resources/action.yaml)) to default to `config.minio.tfbackend` for local `act` runs and override to `config.s3.tfbackend` for cloud CI runs.

**Boundary discipline (AC7) held:** zero edits to either `backend.tf`, either `config.s3.tfbackend`, any `*.tf` file, any workflow, any composite action, `scripts/`, `docker-compose.yaml`, `Makefile`, `act.secrets.example`, `.actrc`, `.gitignore`, `README.md`, `MIGRATION.md`, or `_bmad-output/planning-artifacts/*`. Final byte-equality check (Subtask 6.3) confirms all four pre-existing tfbackend + backend.tf files retain their pre-work digests.

### File List

**New files:**
- `terraform/konnect-teams/config.minio.tfbackend`
- `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend`

**Modified files:**
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status flip + `last_updated` annotation)
- `_bmad-output/implementation-artifacts/2-1-add-config-minio-tfbackend-to-both-terraform-trees-alongside-existing-config-s3-tfbackend.md` (this file — Status, Tasks/Subtasks checkboxes, Dev Agent Record)

### Review Findings

_Source: bmad-code-review, 2026-05-12. Three layers: Blind Hunter (diff-only adversarial), Edge Case Hunter (path enumeration), Acceptance Auditor (AC1–AC8 verification). 24 unique findings after dedup; 15 dismissed as spec-justified noise; 9 surfaced below._

- [x] [Review][Defer] AC6 outer-tree plan rc=1 accepted on intent-satisfaction grounds — deferred, orthogonal pre-existing Vault gap (Story 1.6 precedent). Story file line 119 declares `Exit code 1 is a fail`. Dev Agent Record (line 451) reports rc=1 from a Vault `data "vault_auth_backend"` lookup against an unmounted `auth/github-actions/` path. The plan body itself enumerated cleanly (`Plan: 10 to add, 0 to change, 0 to destroy`, zero churn signals on konnect resources), so the MinIO backend file passed its functional gate. The orthogonal Vault gap is already captured at `deferred-work.md:40` from Story 1.6. AC6 intent (`no provider-schema validation errors from the new config.minio.tfbackend`) is satisfied.

- [x] [Review][Patch] Sprint-status YAML header comment stale after dev work [`_bmad-output/implementation-artifacts/sprint-status.yaml:2`] — Applied. Header comment at line 2 updated to `2026-05-12 (story 2-1: ready-for-dev → in-progress → review → done (code-review complete; 1 patch applied))`, matching the post-review narrative and bumping the date to today.

- [x] [Review][Defer] Same `bucket = "tfstate"` + `key = "konnect.tfstate"` across both trees → state-collision risk [`terraform/konnect-teams/config.minio.tfbackend:9-10`, `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend:9-10`] — deferred, pre-existing pattern. Two Terraform root modules with identical static bucket+key on the same MinIO endpoint would overwrite each other if both initialized verbatim without dynamic `-backend-config="key=…"` overrides. The existing `config.s3.tfbackend` files have the same convention (verified) — workflows pass per-team overrides at init time. Story 2.3 wires `TF_BACKEND_CONFIG` and is the natural place to revisit local-default keying.

- [x] [Review][Defer] No required_version pin / no comment naming the minimum Terraform + AWS-provider versions that accept the `endpoints` block-attribute form [`terraform/konnect-teams/config.minio.tfbackend:12`] — deferred. The story rationale (line 60) names "Terraform ≥ 1.6, AWS provider ≥ 5.x" as the requirement; an older toolchain would silently fail to parse `endpoints = { s3 = ... }`. No `required_version` constraint or in-file comment captures this. Latent-only — current dev environment satisfies it (verified by AC4 rc=0).

- [x] [Review][Defer] Two byte-identical `config.minio.tfbackend` files with no shared source or CI divergence guard [`terraform/konnect-teams/config.minio.tfbackend`, `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend`] — deferred. Architecture mandates two-tree symmetry (architecture.md:345), and Story 2.2 will introduce the `init-terraform` composite action that consumes both. A CI check (`diff -q <outer> <inner>`) to enforce byte-equality going forward is a useful future improvement but is scope leak here.

- [x] [Review][Defer] Hardcoded `secret_key = "minio-root-password"` may trip secret scanners if any are added to CI [`terraform/konnect-teams/config.minio.tfbackend:20`, `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend:20`] — deferred. No gitleaks / trufflehog / pre-commit config exists in the repo today (verified). The hardcoding itself is spec-intentional ("Critical-don't-miss: hardcoded credentials are intentional" — well-known dev-mode root creds already public in `docker-compose.yaml:13-14`). If secret scanners are introduced later, an allowlist entry for `config.minio.tfbackend` will be needed.

- [x] [Review][Defer] IPv6-first hosts may resolve `localhost` to `::1` while MinIO binds `0.0.0.0` [`terraform/konnect-teams/config.minio.tfbackend:12`, `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend:12`] — deferred, operational. On some Linux distributions, `getaddrinfo("localhost")` returns `::1` first; MinIO's docker-compose default binds IPv4 only. Switching to `127.0.0.1` would eliminate the ambiguity but diverges from the human-readable `localhost` and from existing `MIGRATION.md` examples. Surface if a future operator reports a connection-refused on Linux.

- [x] [Review][Defer] Port `9000` collision risk with other host services [`terraform/konnect-teams/config.minio.tfbackend:12`, `.github/actions/provision-konnect-resources/terraform/config.minio.tfbackend:12`] — deferred, operational. Portainer/SonarQube/php-fpm commonly bind 9000. Mitigation belongs in `make prepare` / docker-compose health check, not in the backend-config file. Story 2.6 verification gate is the natural place to add a `nc -z localhost 9000` preflight.

- [x] [Review][Defer] Two parallel `last_updated` representations (header comment + YAML key) kept in sync by hand [`_bmad-output/implementation-artifacts/sprint-status.yaml:2,38`] — deferred, pre-existing convention. The duplication has already produced the stale-comment patch finding above. Single source of truth (or a derived-from-the-other comment) would prevent the class of bug. Pre-dates Story 2.1.
