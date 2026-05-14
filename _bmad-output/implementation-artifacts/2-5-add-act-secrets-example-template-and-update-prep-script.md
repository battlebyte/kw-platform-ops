# Story 2.5: Add `act.secrets.example` template and update prep script

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Solutions Engineer,
I want a committed `act.secrets.example` template documenting every operator-supplied value with placeholders, plus a prep script that creates `act.secrets` from it on first run,
So that I know exactly which credentials I need to supply on a fresh clone, and `act.secrets` itself stays gitignored.

## Acceptance Criteria

### AC1 — `act.secrets.example` created at repo root

**Given** no `act.secrets` file exists in a fresh clone
**When** I create `act.secrets.example` at the repo root
**Then** the file contains, in order:
- `KONNECT_TOKEN=` — with an inline comment pointing at `https://cloud.konghq.com/tokens` as the source for a Konnect personal access token
- `VAULT_TOKEN=root` — with an inline comment noting this is the docker-compose dev-mode default (matching the Vault dev container started by `docker-compose up`)
- `GITHUB_ORG=` — with an inline comment explaining it is used by `vault-pki-setup.sh` to scope role bindings
- `AWS_ACCESS_KEY_ID=minio-root-user` — with an inline comment noting these match the `docker-compose.yaml` MinIO defaults and should only be changed when targeting a real AWS S3 backend (`TF_BACKEND_CONFIG=config.s3.tfbackend`)
- `AWS_SECRET_ACCESS_KEY=minio-root-password` — with the same MinIO-default inline comment
**And** the file is committed to the repository (not gitignored — verify by `git check-ignore act.secrets.example` returning no match)

### AC2 — `act.secrets` remains gitignored

**Given** the `.gitignore` at the repo root containing `*.secrets`
**When** I run `git check-ignore act.secrets`
**Then** the output confirms `act.secrets` is gitignored (non-empty output, exit code 0)
**And** the `.gitignore` file is **not modified** by this story — `*.secrets` already covers `act.secrets`

### AC3 — `prep-act-secrets.sh` rewritten as a non-interactive bootstrap script

**Given** `scripts/prep-act-secrets.sh` currently prompts interactively for many values (KONNECT_PAT, GITHUB_TOKEN, S3_ACCESS_KEY, S3_SECRET_KEY, Docker creds, OIDC issuer, DD_API_KEY, DT_API_TOKEN, KUBE_CONTEXT)
**When** I rewrite the script
**Then** the new script:
- Opens with `#!/bin/bash` and `set -euo pipefail` (match project `scripts/*.sh` convention)
- If `act.secrets` already exists: prints a one-line status message (e.g., `act.secrets already exists — skipping. Edit it directly to update secrets.`) and exits 0 immediately — **does not overwrite**
- If `act.secrets.example` does not exist at `$(dirname "$0")/../act.secrets.example` (relative to the script): prints an error and exits 1
- Otherwise: copies `act.secrets.example` to `act.secrets` via `cp`
- After copying, emits a clear, terminal-friendly message that lists exactly which fields require operator input before workflows can run (at minimum: `KONNECT_TOKEN` and `GITHUB_ORG`); notes that `VAULT_TOKEN` and the AWS/MinIO fields are pre-filled with safe local defaults

### AC4 — `make prepare` on a fresh clone produces a usable `act.secrets`

**Given** a fresh clone with no `act.secrets`
**When** I run `make prepare` (which calls `prep-act-secrets` target → `./scripts/prep-act-secrets.sh`)
**Then** `act.secrets` is created with the contents of `act.secrets.example`
**And** the terminal output clearly directs the operator to fill in `KONNECT_TOKEN` and `GITHUB_ORG` before running any workflow
**And** running `make prepare` a second time (with `act.secrets` now present) does not overwrite the file and exits 0

### AC5 — Boundary discipline

**Given** all changes are complete
**When** I run `git status --short`
**Then** the modified/added set is exactly:
```
A  act.secrets.example
M  scripts/prep-act-secrets.sh
M  _bmad-output/implementation-artifacts/sprint-status.yaml
M  _bmad-output/implementation-artifacts/2-5-add-act-secrets-example-template-and-update-prep-script.md
```
**And** no other files are modified — in particular: `.gitignore`, `Makefile`, all workflow files, all Terraform files, all composite actions, and every other script in `scripts/` are byte-identical pre/post

## Tasks / Subtasks

- [x] Task 1 (Pre-flight) (AC: 2, 5)
  - [x] 1.1 Verify `act.secrets.example` does NOT already exist: `test -f act.secrets.example && echo "EXISTS — check before overwriting" || echo "OK: not present"`
  - [x] 1.2 Confirm `act.secrets` is gitignored and `act.secrets.example` is NOT: `git check-ignore -v act.secrets act.secrets.example` — expect only `act.secrets` to match
  - [x] 1.3 Capture baseline digest for boundary check (AC5): `shasum -a 256 scripts/prep-act-secrets.sh .gitignore Makefile .github/workflows/onboard-konnect-teams.yaml .github/workflows/developer-portal.yaml`
  - [x] 1.4 Read the current `scripts/prep-act-secrets.sh` completely to understand what is being replaced (no preservation needed — full rewrite per story)

- [x] Task 2 (AC1) — Create `act.secrets.example`
  - [x] 2.1 Create `act.secrets.example` at the repo root with the following exact content (no trailing newline issues — end with a single newline after the last line):
    ```
    # Konnect personal access token — obtain at https://cloud.konghq.com/tokens
    KONNECT_TOKEN=

    # HashiCorp Vault token — docker-compose dev-mode default (vault starts with this root token)
    VAULT_TOKEN=root

    # Your GitHub organisation — used by scripts/vault-pki-setup.sh to scope role bindings
    GITHUB_ORG=

    # MinIO / AWS S3 credentials — defaults match the docker-compose.yaml MinIO stack
    # Change to real AWS keys when targeting TF_BACKEND_CONFIG=config.s3.tfbackend
    AWS_ACCESS_KEY_ID=minio-root-user
    AWS_SECRET_ACCESS_KEY=minio-root-password
    ```
  - [x] 2.2 Verify the file is NOT gitignored: `git check-ignore act.secrets.example && echo "FAIL: should not be ignored" || echo "OK: not ignored"`
  - [x] 2.3 Verify the file is well-formed (no accidental secret values, no trailing spaces): `cat -A act.secrets.example` — inspect output

- [x] Task 3 (AC3) — Rewrite `scripts/prep-act-secrets.sh`
  - [x] 3.1 Overwrite `scripts/prep-act-secrets.sh` with the following exact body:
    ```bash
    #!/bin/bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SECRET_FILE="act.secrets"
    EXAMPLE_FILE="${SCRIPT_DIR}/../act.secrets.example"

    if [[ -f "$SECRET_FILE" ]]; then
        echo "act.secrets already exists — skipping. Edit it directly to update secrets."
        exit 0
    fi

    if [[ ! -f "$EXAMPLE_FILE" ]]; then
        echo "ERROR: act.secrets.example not found at ${EXAMPLE_FILE}."
        echo "Ensure the repository is fully checked out and act.secrets.example exists at the repo root."
        exit 1
    fi

    cp "$EXAMPLE_FILE" "$SECRET_FILE"

    cat <<'MSG'

    act.secrets created from act.secrets.example.

    Before running any workflow, open act.secrets and fill in:

      KONNECT_TOKEN   — Required. Your Konnect personal access token.
                        Obtain one at: https://cloud.konghq.com/tokens

      GITHUB_ORG      — Required. Your GitHub organisation name.
                        Used by scripts/vault-pki-setup.sh to scope role bindings.

    The following fields are pre-filled with local docker-compose defaults:

      VAULT_TOKEN=root              (Vault dev container root token)
      AWS_ACCESS_KEY_ID=minio-root-user     (MinIO default credential)
      AWS_SECRET_ACCESS_KEY=minio-root-password  (MinIO default credential)

    Change the AWS_ fields only when targeting a real AWS S3 backend
    (TF_BACKEND_CONFIG=config.s3.tfbackend).

    MSG
    ```
  - [x] 3.2 Ensure the file is executable: `chmod +x scripts/prep-act-secrets.sh`
  - [x] 3.3 Syntax-check: `bash -n scripts/prep-act-secrets.sh && echo "OK: syntax valid"`
  - [x] 3.4 Verify shebang and set flags: `head -2 scripts/prep-act-secrets.sh` — expect `#!/bin/bash` then `set -euo pipefail`

- [x] Task 4 (AC4) — Functional verification
  - [x] 4.1 Simulate fresh clone (move `act.secrets` aside if it exists): `mv act.secrets act.secrets.bak 2>/dev/null || true`
  - [x] 4.2 Run the script: `bash scripts/prep-act-secrets.sh` — expect: file created, operator message printed
  - [x] 4.3 Verify `act.secrets` matches `act.secrets.example`: `diff act.secrets act.secrets.example && echo "OK: identical"`
  - [x] 4.4 Run the script a second time: `bash scripts/prep-act-secrets.sh` — expect: "already exists" message, exit 0, file unchanged
  - [x] 4.5 Restore original `act.secrets` if it was backed up: `mv act.secrets.bak act.secrets 2>/dev/null || true`

- [x] Task 5 (AC5) — Boundary check
  - [x] 5.1 Confirm only the expected files are modified: `git diff --name-only && git ls-files --others --exclude-standard`
  - [x] 5.2 Verify `.gitignore` is unchanged: compare its shasum against the value recorded in Task 1.3
  - [x] 5.3 Verify `Makefile` is unchanged: compare shasum
  - [x] 5.4 Verify workflow files are unchanged: compare shasums

## Dev Notes

### Why This Story Matters

The previous `scripts/prep-act-secrets.sh` was written for an earlier version of the platform that used different secret key names (`KONNECT_PAT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `DD_API_KEY`, `DT_API_TOKEN`, etc.). The current workflows (`onboard-konnect-teams.yaml`, `developer-portal.yaml`) reference `secrets.KONNECT_TOKEN`, `secrets.AWS_ACCESS_KEY_ID`, and `secrets.AWS_SECRET_ACCESS_KEY` — none of which the old interactive script writes. This means any SE running `make prepare` today gets an `act.secrets` that is incompatible with the workflows.

Story 2.5 fixes this fundamental mismatch by replacing the interactive script with a copy-from-example approach that produces an `act.secrets` aligned with what the workflows actually expect.

### Files Being Modified

| File                                                       | Change Type               | Notes                                    |
| ---------------------------------------------------------- | ------------------------- | ---------------------------------------- |
| `act.secrets.example`                                      | **NEW**                   | Committed template; not gitignored       |
| `scripts/prep-act-secrets.sh`                              | **UPDATE (full rewrite)** | Old interactive script replaced entirely |
| `_bmad-output/implementation-artifacts/sprint-status.yaml` | **UPDATE**                | Story status: backlog → ready-for-dev    |

### Files NOT Modified (Boundary)

Do not touch: `.gitignore` (already covers `act.secrets` via `*.secrets`), `Makefile` (already calls `./scripts/prep-act-secrets.sh` — no change needed), any workflow file, any action, any Terraform file, any other script.

### Secret Key Names — Critical Alignment

The new `act.secrets.example` uses the key names that the **current workflows reference**:

| Key                     | Where Used                                                                                                                                                | Source                               |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `KONNECT_TOKEN`         | `secrets.KONNECT_TOKEN` in `onboard-konnect-teams.yaml:22`, `developer-portal.yaml:30`                                                                    | Konnect personal access token        |
| `VAULT_TOKEN`           | `secrets.VAULT_TOKEN` in `onboard-konnect-teams.yaml:30`, `developer-portal.yaml:38`; also `$(grep -o 'VAULT_TOKEN=\K.*' act.secrets)` in Makefile line 4 | Vault root token                     |
| `GITHUB_ORG`            | `$(grep -o 'GITHUB_ORG=\K.*' act.secrets)` in Makefile line 5; passed to `vault-pki-setup.sh`                                                             | GitHub org                           |
| `AWS_ACCESS_KEY_ID`     | `secrets.AWS_ACCESS_KEY_ID` in `onboard-konnect-teams.yaml:51`, `developer-portal.yaml:53`                                                                | MinIO root user / AWS access key     |
| `AWS_SECRET_ACCESS_KEY` | `secrets.AWS_SECRET_ACCESS_KEY` in `onboard-konnect-teams.yaml:52`, `developer-portal.yaml:54`                                                            | MinIO root password / AWS secret key |

The old script wrote `KONNECT_PAT` and `S3_ACCESS_KEY`/`S3_SECRET_KEY` — these keys do not match any current workflow reference and should NOT appear in the new example.

### Gitignore Pattern — Do Not Modify

`act.secrets` is already gitignored by `.gitignore` line 55: `*.secrets`. This pattern also covers any future `*.secrets` files. `act.secrets.example` has extension `.example` and is intentionally NOT gitignored — it must be committed.

### MinIO Default Credentials — Not Secrets

`AWS_ACCESS_KEY_ID=minio-root-user` and `AWS_SECRET_ACCESS_KEY=minio-root-password` are the MinIO default credentials defined in `docker-compose.yaml` (`MINIO_ROOT_USER=minio-root-user`, `MINIO_ROOT_PASSWORD=minio-root-password`). These are not real secrets — they are the local dev stack defaults. They appear in `act.secrets.example` with their default values pre-filled so the SE does not need to look up docker-compose to configure `act`. The inline comment clarifies they only need changing when targeting a real AWS S3 backend.

### Prep Script Architecture Decision

The story replaces the interactive prompt-based approach with a declarative copy-from-template approach. This is intentional and aligned with FR6 ("through a single gitignored local secrets file, without modifying any tracked source") and AR16. The interactive approach required SEs to have all credentials at hand during `make prepare`; the new approach lets them run `make prepare`, then open `act.secrets` and fill in only the two mandatory fields at their own pace before running workflows.

The `SCRIPT_DIR` pattern (`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`) resolves the script's own directory correctly regardless of the working directory from which it is invoked (e.g., `make prep-act-secrets` calls it from the repo root, but `./scripts/prep-act-secrets.sh` invoked directly also works). The example file path is constructed relative to the script directory: `${SCRIPT_DIR}/../act.secrets.example` → resolves to the repo root's `act.secrets.example`.

### Anti-patterns to Avoid

- ❌ Do NOT echo any secret values from `act.secrets` or `act.secrets.example` in the script output (NFR4). The only output is the message telling the operator what to fill in.
- ❌ Do NOT add `|| true` to any command in the new script — it uses `set -euo pipefail`.
- ❌ Do NOT modify `.gitignore` — `*.secrets` already covers `act.secrets`.
- ❌ Do NOT write `KONNECT_PAT` in the example — workflows use `KONNECT_TOKEN`.
- ❌ Do NOT write `S3_ACCESS_KEY` / `S3_SECRET_KEY` — workflows use `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- ❌ Do NOT include `DD_API_KEY` or `DT_API_TOKEN` — Datadog/Dynatrace removal is Epic 5 (Story 5.1), but these keys are already no longer used by any current workflow; including them in the example would imply they're still required.
- ❌ Do NOT include `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `OIDC_ISSUER`, `KUBE_CONTEXT`, `GITHUB_TOKEN` — these are not referenced by any current platform workflow via `secrets.*`.
- ❌ Do NOT mark `AWS_SESSION_TOKEN` as required — it is used only for real AWS STS authentication, not for MinIO. It is optional and should not appear in the example.

### Previous Story Context (Story 2.4)

Story 2.4 renamed `create-s3-bucket.sh` → `create-state-bucket.sh` and introduced dual-mode MinIO/AWS support. The script requires `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (set as env vars, not script arguments). In `act` mode these come from `act.secrets` → workflow env via `aws-actions/configure-aws-credentials@v4`. The example must therefore include these AWS env var names (not `S3_ACCESS_KEY`/`S3_SECRET_KEY` from the old script).

### Testing Approach

This repo has no unit-test framework. Validation for this story is:
1. **Syntax check**: `bash -n scripts/prep-act-secrets.sh`
2. **Functional test**: simulate fresh clone by temporarily renaming `act.secrets`, run the script, verify the resulting file matches the example, run the script again to confirm idempotency
3. **Gitignore test**: `git check-ignore act.secrets.example` (must return nothing / non-zero) and `git check-ignore act.secrets` (must return match)
4. **Boundary check**: `git diff --name-only` shows only expected files

### Project Structure Notes

- `act.secrets.example` goes at the **repo root** (same level as `act.secrets`, `docker-compose.yaml`, `Makefile`)
- `scripts/prep-act-secrets.sh` is already in the correct location
- The `SCRIPT_DIR` pattern in the new script is consistent with how `scripts/check-deps.sh` and other scripts in this repo resolve relative paths

### References

- AR16: `act.secrets.example` template requirement [Source: `_bmad-output/planning-artifacts/epics.md` — Additional Requirements]
- FR6: Single-credential bootstrap via gitignored local secrets file [Source: `_bmad-output/planning-artifacts/epics.md` — Functional Requirements]
- AR15: Vault is the secrets backend; local default = `VAULT_TOKEN=root` pointing at `http://localhost:8300` [Source: `_bmad-output/planning-artifacts/epics.md` — Additional Requirements]
- Workflow secret references: `onboard-konnect-teams.yaml` lines 22, 30, 51-53; `developer-portal.yaml` lines 30, 38, 53-55 [Source: `.github/workflows/onboard-konnect-teams.yaml`, `.github/workflows/developer-portal.yaml`]
- Makefile `VAULT_TOKEN`/`GITHUB_ORG` grep pattern: lines 4-5 [Source: `Makefile`]
- MinIO default credentials: `MINIO_ROOT_USER=minio-root-user`, `MINIO_ROOT_PASSWORD=minio-root-password` [Source: `docker-compose.yaml`]
- `.gitignore` line 55: `*.secrets` [Source: `.gitignore`]
- Previous story dev notes: Story 2.4 [Source: `_bmad-output/implementation-artifacts/2-4-rename-create-s3-bucket-sh-create-state-bucket-sh-with-minio-aws-support.md`]
- Project bash conventions: `set -euo pipefail`, `shell: bash`, OS detection [Source: `_bmad-output/project-context.md` — Language-Specific Rules / Bash]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4.6 (GitHub Copilot)

### Debug Log References

N/A — no blockers encountered.

### Completion Notes List

- ✅ Task 1: Pre-flight confirmed — `act.secrets.example` did not exist, `act.secrets` is gitignored by `.gitignore:55:*.secrets`, baseline hashes captured for `.gitignore`, `Makefile`, and both workflow files.
- ✅ Task 2: Created `act.secrets.example` at repo root with all 5 required keys and inline comments. File is not gitignored. No trailing spaces, Unix line endings.
- ✅ Task 3: Fully rewrote `scripts/prep-act-secrets.sh` — replaced interactive prompt-based script with declarative copy-from-template approach. Uses `set -euo pipefail`, `SCRIPT_DIR` pattern for path resolution, idempotency guard, and clear operator instructions. File is executable, syntax valid.
- ✅ Task 4: Functional verification passed — fresh-clone simulation produced `act.secrets` identical to `act.secrets.example`; second run emitted "already exists" skip message; original `act.secrets` restored.
- ✅ Task 5: Boundary check passed — only `scripts/prep-act-secrets.sh` (modified) and `act.secrets.example` (new) changed; `.gitignore`, `Makefile`, `onboard-konnect-teams.yaml`, and `developer-portal.yaml` hashes identical to baseline.

### File List

- `act.secrets.example` — NEW. Committed template with all 5 required keys and inline comments.
- `scripts/prep-act-secrets.sh` — MODIFIED. Full rewrite from interactive to copy-from-template bootstrap script.

### Review Findings

- [x] [Review][Patch] SECRET_FILE uses a bare relative path — anchor to repo root via SCRIPT_DIR [scripts/prep-act-secrets.sh]
- [x] [Review][Patch] No chmod 600 after cp — act.secrets created with world-readable permissions [scripts/prep-act-secrets.sh]
- [x] [Review][Patch] No ERR trap — cp failure leaves a partial act.secrets that blocks future runs [scripts/prep-act-secrets.sh]
- [x] [Review][Patch] EXAMPLE_FILE readability not checked before cp — -f does not test read permission [scripts/prep-act-secrets.sh]
- [x] [Review][Defer] Broken symlink at $SECRET_FILE — [[ -f ]] guard returns false, cp follows dangling symlink [scripts/prep-act-secrets.sh] — deferred, pre-existing
- [x] [Review][Defer] BASH_SOURCE[0] empty when script is piped to bash — SCRIPT_DIR resolves to CWD instead of script dir [scripts/prep-act-secrets.sh] — deferred, pre-existing
- [x] [Review][Defer] Directory named act.secrets in CWD — cp copies example into directory silently [scripts/prep-act-secrets.sh] — deferred, pre-existing
