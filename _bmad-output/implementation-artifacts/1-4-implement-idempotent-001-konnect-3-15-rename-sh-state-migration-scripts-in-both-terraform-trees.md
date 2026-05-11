# Story 1.4: Implement idempotent `001-konnect-3-15-rename.sh` state-migration scripts in both Terraform trees

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want idempotent state-migration scripts at the canonical P6 path in **both** Terraform trees that wrap every `terraform state mv` / `state rm` / `import` required by the Konnect provider 3.1.0 → 3.15.0 hop with `terraform state list | grep` preconditions,
so that operators with existing state can upgrade in place without resource destruction, the scripts can be safely re-run on already-migrated state, and Stories 1.5 (`make migrate-state` driver) and 1.6 (clean-plan verification + `MIGRATION.md` §2) have a stable input contract.

This story is **script-authoring only**. It does **not** implement `make migrate-state` (Story 1.5), does **not** create the applied-marker file `.terraform/migrations-applied` (Story 1.5 — and the path is already gitignored via `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2), so no `.gitignore` change is needed in this story), does **not** run a stateful `terraform plan` against MinIO or S3 (Story 1.6's gate), and does **not** edit `MIGRATION.md` (Story 1.6 owns §2).

**Critical input from Story 1.1 audit:** the per-tree `state mv`/`rm`/`import` operation count for the 3.1.0 → 3.15.0 hop is **zero** ([`1-1-konnect-3-15-audit.md:22`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md#L22)). The 3.0.0 `konnect_portal` v2 → v3 import-into-`konnect_portal_classic` migration is already past the 3.1.0 baseline. **The script bodies are therefore idempotent no-ops with explanatory comments — not actual `terraform state mv` invocations.** The P6 header/marker convention still has to land in this story so that (a) Story 1.5's driver has a uniform target shape and (b) any future provider bump that *does* require state operations slots in as `migrations/002-*.sh` against an already-established convention.

## Acceptance Criteria

1. **AC1 — Two scripts created at the canonical P6 paths.**
   - [`terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh) is created (outer tree).
   - [`.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`](.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh) is created (inner tree).
   - Both `migrations/` directories are created in this story (neither exists today — verified via `ls`).
   - Both scripts are committed with mode `0755` (executable). After commit, `git ls-files --stage` shows mode `100755` for both paths. macOS gotcha: `chmod +x` is sufficient; do **not** rely on `git update-index --chmod=+x` if the working-tree mode is already correct, and do **not** disable `core.fileMode` in this PR.

2. **AC2 — P6 header convention satisfied in both scripts.**
   - First line: `#!/usr/bin/env bash`.
   - Second line: `set -euo pipefail`.
   - Header comment block (between the shebang/`set` and any executable code) declares, in this order:
     - **Purpose:** "Konnect provider state migration: 3.1.0 → 3.15.0".
     - **Source provider version:** `kong/konnect 3.1.0`.
     - **Target provider version:** `kong/konnect 3.15.0`.
     - **Prerequisites:** `terraform init -upgrade` already run in this tree (so the new provider is downloaded and the state schema is loaded by the right plugin); operator has read access to whatever backend this tree's `backend.tf` is currently pointed at.
     - **Idempotency note:** explicit one-paragraph statement that re-running on already-migrated state is safe and produces zero state operations; every `terraform state mv` / `state rm` / `import` (when there are any) is preceded by a `terraform state list | grep -F <address>` precondition check.
   - Header references the audit deliverable [`_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md) so future maintainers can see *why* the body is empty.

3. **AC3 — Body shape demonstrates the guard pattern even though it is a no-op for this hop.**
   - Per the Story 1.1 audit ([`1-1-konnect-3-15-audit.md:22`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md#L22)), the operation count for this hop is **zero** across both trees: `state mv = 0`, `state rm = 0`, `import = 0`. **Do not invent operations.**
   - Each script's body is a no-op section that:
     - Defines a small Bash helper function (e.g., `state_has() { terraform state list | grep -Fxq -- "$1"; }`) that demonstrates the canonical guard pattern future migrations must use. The helper must use `grep -Fx` (fixed-string, full-line match) — substring matches will false-positive on resources whose addresses share a prefix.
     - Contains a clearly-marked, commented-out template showing what an actual `state mv` invocation would look like, e.g.:
       ```bash
       # if state_has 'module.foo.konnect_old_resource.this'; then
       #   terraform state mv 'module.foo.konnect_old_resource.this' 'module.foo.konnect_new_resource.this'
       # fi
       ```
     - Prints a single explanatory line to stderr at run-time (e.g., `echo "[migration 001] no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see 1-1-konnect-3-15-audit.md)" >&2`) so an operator running `bash 001-konnect-3-15-rename.sh` directly sees confirmation rather than silence.
     - Exits `0` at the end (implicit through `set -e`-friendly final command; no explicit `exit 1` paths in this story's bodies because there are no operations to fail).
   - **Do not** add `terraform plan`, `terraform apply`, `terraform init`, or any non-`state list`-read invocation inside the script body. The script reads state, never mutates it for this hop.
   - **Do not** require a working backend connection to *run* the script — for a zero-op body, `terraform state list` against a nonexistent backend will fail; the script must therefore handle the "no initialized backend" case gracefully. Implementation: skip the `state_has` call entirely on the no-op path; the helper is defined for future-proofing only. (When 002+ migrations land with real ops, they will require an initialized backend; that is the right call site to enforce it. Do not enforce it here.)

4. **AC4 — Idempotency property — verified by direct re-run.**
   - Running each script once on any state (pre-migration, mid-migration, or already-migrated) produces zero state operations and exits `0`.
   - Running each script a second time on the same state produces identical output (the explanatory stderr line + zero state operations) and exits `0`.
   - Verification command (run from the affected tree's root, both trees in turn):
     ```bash
     bash migrations/001-konnect-3-15-rename.sh
     echo "first run rc: $?"
     bash migrations/001-konnect-3-15-rename.sh
     echo "second run rc: $?"
     ```
     Expected: both exit codes `0`; stderr line printed twice; no `state mv`/`state rm`/`import` in either run.

5. **AC5 — `terraform plan` parity (vacuous for this hop, but verified).**
   - Per the epic AC4 ("Given the script has run successfully / When I run `terraform plan` afterwards in the affected tree / Then the plan shows zero diffs for every resource the script touched"): because the script touches zero resources, the assertion is vacuously true. **No live-state plan is required in this story.** The full clean-plan-against-MinIO gate is Story 1.6's responsibility ([`epics.md#Story 1.6`](_bmad-output/planning-artifacts/epics.md)).
   - Do not attempt a stateful `terraform plan` for this story. The Story 1.3 dev-agent record documented that the inner tree's root [`main.tf:95`](.github/actions/provision-konnect-resources/terraform/main.tf#L95) `data "terracurl_request" "fetch_team"` is unguarded against dummy tokens and blocks a refresh-less plan; that is a Story 1.6 / future-cleanup concern, not this story's.

6. **AC6 — Boundary discipline.**
   - **No edits** to `Makefile` (Story 1.5 owns `migrate-state`).
   - **No edits** to `MIGRATION.md` (Story 1.6 owns §2; the file does not yet exist).
   - **No edits** to `.gitignore` (`.terraform/migrations-applied` is already covered by `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2); verify with `git check-ignore -v terraform/konnect-teams/.terraform/migrations-applied` and capture in the Debug Log — do **not** add a duplicate rule).
   - **No edits** under `terraform/konnect-teams/*.tf`, `terraform/konnect-teams/modules/**`, `.github/actions/provision-konnect-resources/terraform/*.tf`, or `.github/actions/provision-konnect-resources/terraform/modules/**` (Stories 1.2 and 1.3 own those; the bumps are already merged).
   - **No edits** to `.github/workflows/**` or `.github/actions/**/action.yml` / `action.yaml` (Story 1.5 / Epic 2/4 territory).
   - **No new files** beyond the two scripts and the two `migrations/` directories implied by them. No `README.md` inside `migrations/` (the script header carries the documentation; an Epic-1 retrospective or Story 1.6 can add one if useful — out of scope here).

7. **AC7 — Sprint status updated.**
   - On story completion (after `dev-story` execution and pre-`code-review`), [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml) `1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees` moves `ready-for-dev` → `review` (the dev agent's `code-review` workflow advances it to `done`). Bump `last_updated`. Preserve every other comment and the `STATUS DEFINITIONS` block.
   - This story file's `Status:` field at line 3 moves `ready-for-dev` → `in-progress` → `review` in step.

## Tasks / Subtasks

- [x] **Task 1: Confirm pre-conditions and the zero-op input** (AC: 3, 6)
  - [x] Subtask 1.1 — Read [`_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md) lines 7–32 (the Summary). Confirm: state-migration operation count = 0, classification counts = 39 `no-change` + 1 `deprecation-flagged` + 0 `attribute-edit-required` + 0 `state-mv-required`. If the audit has been amended since this story was written and the operation count is no longer 0, **stop and surface the discrepancy in Completion Notes before proceeding** — do not fabricate operations.
  - [x] Subtask 1.2 — Verify neither `migrations/` directory exists yet:
    ```bash
    ls terraform/konnect-teams/migrations/ 2>/dev/null && echo "EXISTS — stop and audit"
    ls .github/actions/provision-konnect-resources/terraform/migrations/ 2>/dev/null && echo "EXISTS — stop and audit"
    ```
    Expected: both lines silent (directories absent). If either exists, audit before overwriting.
  - [x] Subtask 1.3 — Confirm `.terraform/migrations-applied` is already gitignored without a new rule:
    ```bash
    git check-ignore -v terraform/konnect-teams/.terraform/migrations-applied
    git check-ignore -v .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
    ```
    Expected: both return `.gitignore:2:**/.terraform/*` (or equivalent line citing the `**/.terraform/*` rule). Capture both lines for the Debug Log. **Do not** add a redundant rule.

- [x] **Task 2: Author the outer-tree script** (AC: 1, 2, 3)
  - [x] Subtask 2.1 — Create [`terraform/konnect-teams/migrations/`](terraform/konnect-teams/migrations) directory. (`mkdir -p`.)
  - [x] Subtask 2.2 — Author [`terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh). Use the exact body shape in **Dev Notes — Script template (canonical body)** below. The script must be byte-identical to the inner-tree counterpart **except** for the one-line "tree" identifier in the stderr message (e.g., `terraform/konnect-teams`) and the audit cross-reference can stay identical (one audit covers both trees).
  - [x] Subtask 2.3 — Make the script executable:
    ```bash
    chmod +x terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh
    ```
  - [x] Subtask 2.4 — `bash terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh` runs to exit 0 even from a tree with no `.terraform/` directory initialized. (The no-op body must not require an initialized backend — see AC3.)

- [x] **Task 3: Author the inner-tree script** (AC: 1, 2, 3)
  - [x] Subtask 3.1 — Create [`.github/actions/provision-konnect-resources/terraform/migrations/`](.github/actions/provision-konnect-resources/terraform/migrations) directory.
  - [x] Subtask 3.2 — Author [`.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`](.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh) following the same template. Tree-identifier in the stderr message: `.github/actions/provision-konnect-resources/terraform`.
  - [x] Subtask 3.3 — Make the script executable: `chmod +x .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`.
  - [x] Subtask 3.4 — `bash .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh` runs to exit 0 from the inner tree without requiring `init` or live state.

- [x] **Task 4: Idempotency verification** (AC: 4)
  - [x] Subtask 4.1 — From each tree's root, run the script twice in sequence (per AC4 verification command). Confirm both runs exit 0 and emit identical stderr. Capture both runs verbatim in the Debug Log.
  - [x] Subtask 4.2 — Optional but encouraged: with `terraform init -backend=false` already run in the outer tree (cheap, no backend dependency), confirm the helper-function path is exercised when `terraform state list` is callable. Manually invoke `terraform state list` once to confirm it returns "No state file was found!" (acceptable for an empty state) — the helper does not need to be invoked from the no-op body, so this is informational only. *(Skipped — informational only and not required by AC; no-op body never invokes the helper.)*

- [x] **Task 5: Permissions, executable bit, and Git scope verification** (AC: 1, 6)
  - [x] Subtask 5.1 — Confirm the executable bit landed:
    ```bash
    git ls-files --stage \
      terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh \
      .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh
    ```
    Expected: both lines start with `100755`. If either is `100644`, run `git update-index --chmod=+x <path>` and re-stage.
  - [x] Subtask 5.2 — Confirm `git diff --stat` shows **only** these two new files (plus this story file and `sprint-status.yaml`). Anything else is a scope violation per AC6 — audit and revert.
  - [x] Subtask 5.3 — Confirm `.gitignore` is **not** in the diff:
    ```bash
    git diff --stat .gitignore
    ```
    Expected: empty.
  - [x] Subtask 5.4 — Run `shellcheck` on both scripts if available:
    ```bash
    shellcheck terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh
    shellcheck .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh
    ```
    Expected: zero findings, or only [SC2317](https://www.shellcheck.net/wiki/SC2317) ("unreachable command" — expected because the only callable code in the no-op body is the stderr `echo`; the helper function is defined-but-not-called by design). Do **not** add `# shellcheck disable=` directives to silence other findings; fix them instead.

- [x] **Task 6: Story hand-off** (AC: 7)
  - [x] Subtask 6.1 — Update [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml): this story's key from `ready-for-dev` → `review`. Bump `last_updated`. Preserve all comments and the STATUS DEFINITIONS block.
  - [x] Subtask 6.2 — Update this story's `Status:` field at line 3 from `ready-for-dev` → `review`.
  - [x] Subtask 6.3 — Tick every AC1–AC7 box in the PR description with file path / command output references. *(PR description owned by the human; AC1–AC7 verification captured in Completion Notes below.)*

## Dev Notes

### Why this story exists

The architecture decision D3 ([`architecture.md:177`](_bmad-output/planning-artifacts/architecture.md#L177)) and pattern P6 ([`architecture.md:310`](_bmad-output/planning-artifacts/architecture.md#L310)) jointly mandate a per-tree `migrations/NNN-<short-desc>.sh` convention so that future provider bumps slot in as `002-*.sh`, `003-*.sh`, … against a stable shape. Story 1.5 will then add a `make migrate-state` driver that scans both trees in order (outer first, then inner — see [`architecture.md:576`](_bmad-output/planning-artifacts/architecture.md#L576)) and writes `.terraform/migrations-applied` markers. Story 1.6 verifies the end-to-end gate against MinIO and authors `MIGRATION.md` §2.

The 3.1.0 → 3.15.0 hop is a special case: the Story 1.1 audit confirmed via per-resource diff against the local provider source at `/Users/jordi.fernandez/github/terraform-provider-konnect` that **zero `state mv`, `state rm`, or `import` operations** are required across either tree. The hop is purely additive on the schema axis. The `konnect_portal` v2 → v3 migration (3.0.0 BREAKING) is already past the 3.1.0 baseline.

This means the script bodies for `001-konnect-3-15-rename.sh` are no-ops. **The convention still has to land** so that Story 1.5's driver has something to find, and so that future bumps don't need to invent the convention from scratch.

### What this story does NOT do

- It does **not** edit any Terraform HCL (Stories 1.2 and 1.3 already landed the bumps).
- It does **not** add the `make migrate-state` driver to `Makefile` (Story 1.5).
- It does **not** create the `.terraform/migrations-applied` marker file or its writer logic (Story 1.5 — the marker is *written by* the driver, not by the per-migration scripts; per-migration scripts are pure-state-mutation contracts).
- It does **not** modify `.gitignore`. `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2) already covers the future marker path.
- It does **not** edit `MIGRATION.md` (Story 1.6).
- It does **not** add a `README.md` inside either `migrations/` directory.
- It does **not** run a stateful `terraform plan` against MinIO or S3 (Story 1.6).
- It does **not** rewrite `konnect_portal_auth` to use `konnect_identity_provider` (the 3.4.3-deprecation migration; carried as deferred work since Story 1.1).
- It does **not** fix the [`api_implementation`](.github/actions/provision-konnect-resources/terraform/modules/api_implementation/main.tf) module schema rot (deferred from Story 1.3 review).
- It does **not** regenerate [`schema.json`](.github/actions/provision-konnect-resources/terraform/schema.json) (deferred from Story 1.3 review).
- It does **not** add a dummy-token guard to [`fetch_team`](.github/actions/provision-konnect-resources/terraform/main.tf) at root `main.tf:95` (deferred from Story 1.3 review).

### Confirmed file inventory for this story

```
kw-platform-ops/
├── terraform/konnect-teams/
│   └── migrations/                                   ← NEW directory
│       └── 001-konnect-3-15-rename.sh                ← NEW (mode 0755)
└── .github/actions/provision-konnect-resources/terraform/
    └── migrations/                                   ← NEW directory
        └── 001-konnect-3-15-rename.sh                ← NEW (mode 0755)
```

Plus the standard tracking files:
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (`1-4-...` flips `ready-for-dev` → `review`; `last_updated` bumped).
- `_bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md` (this story file: tasks/subtasks ticked, Dev Agent Record filled, Status → review).

**Total expected `git diff --stat` scope:** 2 new shell scripts + 2 sprint/story tracking edits. **Nothing else.**

### Script template (canonical body)

The two scripts must be near-byte-identical. Use this template; substitute the tree-identifier on the marked line. **No additional logic, no extra commentary, no shellcheck directives.**

```bash
#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Migration 001 — Konnect provider 3.1.0 -> 3.15.0
#
# Purpose:
#   Per-tree state migration script for the Konnect Terraform provider hop
#   3.1.0 -> 3.15.0. Invoked by `make migrate-state` (Story 1.5) which writes
#   `.terraform/migrations-applied` on success.
#
# Source provider version: kong/konnect 3.1.0
# Target provider version: kong/konnect 3.15.0
#
# Prerequisites:
#   - `terraform init -upgrade` has been run in this tree (so the 3.15.0
#     provider plugin is downloaded and the state schema is loaded by the
#     correct binary).
#   - Operator has read access to the backend this tree's `backend.tf` is
#     currently pointed at (for trees that are state-bearing — this script's
#     no-op body for the 3.1.0 -> 3.15.0 hop does NOT require an initialized
#     backend).
#
# Idempotency:
#   This script is safe to re-run. Every `terraform state mv` / `state rm` /
#   `import` is preceded by a `terraform state list | grep -Fxq` precondition,
#   so already-migrated state is a zero-op pass. For the 3.1.0 -> 3.15.0 hop,
#   the audit deliverable below confirms operation count = 0 across both
#   Terraform trees; the body therefore demonstrates the canonical guard
#   pattern without invoking any `state` mutation. Re-running on any state
#   produces zero state operations and exits 0.
#
# Audit reference:
#   _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md
#   (Story 1.1; classification: 39 no-change + 1 deprecation-flagged + 0
#   attribute-edit-required + 0 state-mv-required across the two trees.)
# ------------------------------------------------------------------------------
set -euo pipefail

# Canonical guard helper for future migrations. Use grep -Fx (fixed-string,
# full-line match) to avoid false positives on prefix-sharing addresses.
# Defined here as the convention for migrations 002+; intentionally unused
# in the 3.1.0 -> 3.15.0 no-op body.
state_has() {
  terraform state list | grep -Fxq -- "$1"
}

# Template for future migrations (commented out — no operations required for
# the 3.1.0 -> 3.15.0 hop, per audit):
#
# if state_has 'module.<m>.konnect_<old>.<name>'; then
#   terraform state mv \
#     'module.<m>.konnect_<old>.<name>' \
#     'module.<m>.konnect_<new>.<name>'
# fi

echo "[migration 001] tree=<TREE-IDENTIFIER>: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)" >&2
```

Replacement values:
- Outer tree (`terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh`): `<TREE-IDENTIFIER>` → `terraform/konnect-teams`.
- Inner tree (`.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`): `<TREE-IDENTIFIER>` → `.github/actions/provision-konnect-resources/terraform`.

Both scripts use the same audit cross-reference path; one audit document covers both trees.

### Architecture compliance

From [`architecture.md`](_bmad-output/planning-artifacts/architecture.md):

- **D3 — Konnect Provider Migration (3.1.0 → 3.15)** ([`architecture.md:177`](_bmad-output/planning-artifacts/architecture.md#L177)): single-PR migration; verification gate is "`terraform plan` against a fresh local MinIO backend shows zero diffs." That gate is Story 1.6, **not** this story. This story lays the script-shape contract that Story 1.5's driver and Story 1.6's verification both depend on.
- **P6 — Terraform state-migration script convention** ([`architecture.md:310-315`](_bmad-output/planning-artifacts/architecture.md#L310-L315)):
  - **Path:** `terraform/<domain>/migrations/NNN-<short-desc>.sh` (zero-padded sequential).
  - **Header:** `set -euo pipefail` and a comment block stating purpose, source/target provider versions, prerequisites, idempotency notes — all four required.
  - **Idempotent:** re-running on the same state must be safe. Guard every `terraform state mv` / `state rm` / `import` with a `terraform state list | grep` check.
  - **Driver:** invoked via `make migrate-state` (Story 1.5). Applied marker file at `.terraform/migrations-applied` (gitignored — already covered by `**/.terraform/*`).
- **Two-Terraform-tree reality** ([`architecture.md:343`](_bmad-output/planning-artifacts/architecture.md#L343)): both trees follow identical conventions; this story authors a script in each.
- **Anti-pattern: non-idempotent state-migration scripts** ([`architecture.md:334`](_bmad-output/planning-artifacts/architecture.md#L334)): "re-running on a clean checkout must succeed." AC4 is the explicit verification of this property.
- **Project structure** ([`architecture.md:379`](_bmad-output/planning-artifacts/architecture.md#L379), [`:412`](_bmad-output/planning-artifacts/architecture.md#L412)): the target tree post-refactor places `migrations/001-konnect-3-15-rename.sh` exactly where this story creates them.

### Project context compliance

From [`_bmad-output/project-context.md`](_bmad-output/project-context.md):

- **Bash discipline (Language-Specific Rules — Bash):**
  - Always declare `shell: bash` on every step in composite actions — *not* applicable here (this is a standalone script, not a composite-action step).
  - Use `set -euo pipefail` in `scripts/*.sh` and any non-trivial action step. **Required by both AC2 and the project context.**
  - Detect OS before downloading binaries: not applicable (this script downloads nothing).
  - Never `echo` secrets into logs. The script emits only its own diagnostic line — no secrets touched.
- **Standard apply pipeline** (Terraform / HCL): `init -upgrade` → `plan -out=tfplan` → `apply -auto-approve tfplan`. The migration script slots in *before* the next `init`/`plan` cycle in operator-driven runs and is invoked by Story 1.5's `make migrate-state` outside the `init`/`plan`/`apply` chain.
- **No inline comments unless the why is non-obvious.** The header comment is non-obvious (declares versions, prerequisites, idempotency contract) — keep. The commented-out future-migration template is non-obvious (shows the canonical guard pattern) — keep. Do not add inline comments inside the helper function or around `set -euo pipefail` (the why is obvious).
- **Anti-patterns to avoid** (Critical Don't-Miss Rules):
  - ❌ "Adding `continue-on-error: true` or `|| true` to validators…" Equivalent for shell scripts: **do not** swallow errors. The script's `set -euo pipefail` plus the absence of `||` short-circuits in the body is the right shape.
  - ❌ "Echoing secrets to logs." The script emits only the static diagnostic line — confirmed safe.
- **File and folder organization:** `scripts/<helper>.sh` is the location for repo-wide helper scripts. The migration scripts live under each Terraform tree's `migrations/` directory by P6 convention — this is the *correct* exception to the `scripts/` rule, not a violation. Keep one purpose per directory: `migrations/` holds only state migration scripts.

### Carryover from prior stories

**Story 1.1 (audit, done 2026-05-08):**
- Operation count = 0 for the 3.1.0 → 3.15.0 hop. The script bodies for this story are no-ops by definition. Re-confirm against `1-1-konnect-3-15-audit.md` Summary in Subtask 1.1 before authoring; if the audit is amended, surface the discrepancy before fabricating operations.

**Story 1.2 (outer-tree HCL bump, done 2026-05-08):**
- Outer tree is now on `kong/konnect = 3.15.0` exact. The migration script slots in *after* this bump.
- `.terraform.lock.hcl` is gitignored ([`.gitignore:40`](.gitignore#L40)). The migration script does not interact with the lockfile.
- "Story file must be `git add`-ed." Re-confirmed for this story too.

**Story 1.3 (inner-tree HCL bump, done 2026-05-09):**
- Inner tree is now on `kong/konnect = 3.15.0` exact across root + 39 modules.
- The inner-tree root [`main.tf:95`](.github/actions/provision-konnect-resources/terraform/main.tf#L95) `data.terracurl_request.fetch_team` is unguarded against dummy tokens. **This does not affect the migration script** — the script does not invoke `terraform plan` and does not require an initialized backend on the no-op path. It *would* affect Story 1.6's gate; deferred there.
- The local-backend override trick (writing a temporary `backend_override.tf`) was needed for Stories 1.2 / 1.3's refresh-less plan. **Not needed for this story** — the migration script body for this hop is zero-op and does not require an initialized backend.
- Two modules (`api_implementation/`, `api_specification/`) ship without complete `variables.tf`. Pre-existing latent issue. **Out of scope** for this story.

**Pattern across 1.1 / 1.2 / 1.3:** every story keeps its diff scope tight to what its ACs name. Resist the urge to fix unrelated rot in this PR — `git diff --stat` should show **only** the two new scripts + tracking files. AC6 enforces this.

### Pre-known dev-agent traps

The dev agent for this story is at high risk of one specific over-implementation: **inventing state-migration operations to "make the script meaningful."** The story's most important guardrail is *not* doing that. The audit established the operation count is zero. The script body is intentionally empty of operations. Future migrations against future provider versions will fill in the body shape using the same `state_has` helper. That is the design.

Other traps:

- Adding the `make migrate-state` target to `Makefile` "while we're here" — **don't**. Story 1.5.
- Authoring `MIGRATION.md` §2 "while we're here" — **don't**. Story 1.6.
- Creating `.terraform/migrations-applied` from inside the migration script — **don't**. The marker is the driver's responsibility (Story 1.5); per-migration scripts are state-mutation contracts only.
- Adding a duplicate `.gitignore` rule for `.terraform/migrations-applied` — **don't**. Already covered by `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2).
- Asserting initialized-backend / running `terraform init` from inside the script — **don't**. The header documents the prerequisite; enforcement belongs in the driver (Story 1.5) or in a future migration whose body actually requires it.
- Running `terraform plan` from inside the script — **don't**. Migrations are pre-`plan`, not entwined with it. Verification is Story 1.6.
- Adding shellcheck-suppression comments to silence findings — **don't**. Fix the underlying issue or document why the finding is irrelevant in the Debug Log.
- Renaming the script to drop the `001-` prefix or changing the path to `state/` or `migrations.d/` — **don't**. P6 prescribes the exact path and prefix.
- Combining the two scripts into one shared helper sourced by both — **don't**. Each tree's migration is self-contained by P6 design (the driver scans each tree independently).

### Testing standards

This story produces a shell script, not application code. No unit-test framework involved. The "tests" are mechanical:

1. **Static (this story's gate):** both scripts have `mode 0755`, the canonical header, `set -euo pipefail`, `#!/usr/bin/env bash` shebang. `shellcheck` is clean (or only emits the expected SC2317 for the deliberately-unused `state_has` helper).
2. **Idempotency (this story's gate, AC4):** both scripts run twice in a row from each tree's root and produce identical output, exit 0 both times, and emit zero `state` mutations.
3. **Driver integration (Story 1.5's gate):** `make migrate-state` invokes both scripts in order (outer → inner) and writes `.terraform/migrations-applied`. Out of scope here.
4. **Live state plan (Story 1.6's gate):** `terraform plan` against MinIO local backend after `make migrate-state` shows zero diffs in both trees. Out of scope here.

### Project Structure Notes

- The story file goes in `_bmad-output/implementation-artifacts/` (sibling to the audit, sprint-status, prior stories). Same pattern as Stories 1.1–1.3.
- The two new scripts colocate inside their respective Terraform trees per P6. No new files outside those trees (excluding `_bmad-output/...` story-tracking files).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.4] — story BDD acceptance criteria (epic file).
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1] — Epic 1 goal and FR/NFR coverage.
- [Source: _bmad-output/planning-artifacts/architecture.md#D3 — Konnect Provider Migration (3.1.0 → 3.15)] — migration decision and verification gate.
- [Source: _bmad-output/planning-artifacts/architecture.md#P6 — Terraform state-migration script convention] — exact path, header, idempotency, and driver-marker contract.
- [Source: _bmad-output/planning-artifacts/architecture.md#Two-Terraform-tree reality] — why two scripts (one per tree).
- [Source: _bmad-output/planning-artifacts/architecture.md#Decision Impact Analysis] — Story 1.4 follows Stories 1.2 / 1.3 in the D3 sequence.
- [Source: _bmad-output/planning-artifacts/architecture.md#Anti-patterns specific to this architecture] — "non-idempotent state-migration scripts" anti-pattern.
- [Source: _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md] — Story 1.1 deliverable; operation count = 0 is the input contract for this story's no-op body.
- [Source: _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md#Summary] — explicit "Story 1.4's `001-konnect-3-15-rename.sh` scripts are still required to land the standard header/marker convention, but their bodies remain idempotent no-ops with explanatory comments rather than actual `terraform state mv` invocations."
- [Source: _bmad-output/implementation-artifacts/1-2-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-terraform-konnect-teams.md] — outer-tree bump precedent.
- [Source: _bmad-output/implementation-artifacts/1-3-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-github-actions-provision-konnect-resources-terraform.md] — inner-tree bump precedent and review-surface deferred items.
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — running list of deferred items from prior stories.
- [Source: _bmad-output/project-context.md#Bash (in composite actions and scripts)] — `set -euo pipefail` discipline; secrets-in-logs prohibition.
- [Source: _bmad-output/project-context.md#Anti-patterns to avoid] — `|| true` / `continue-on-error` prohibition (shell-script equivalent enforced by `set -e`).
- [Source: .gitignore#L2] — `**/.terraform/*` covers `.terraform/migrations-applied` without a new rule.
- [Source: .gitignore#L40] — `.terraform.lock.hcl` already gitignored (informational).
- [Source: Makefile] — current top-level targets; `migrate-state` target is **not** added in this story (Story 1.5 owns it).

## Dev Agent Record

### Agent Model Used

claude-opus-4-7[1m] (Anthropic Claude Opus 4.7, 1M context) — 2026-05-10

### Debug Log References

**Subtask 1.1 — Audit re-confirmation** (`_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md` line 22):
> State-migration operation count (AC3): **0**. … Story 1.4's `001-konnect-3-15-rename.sh` scripts are still required to land the standard header/marker convention, but their bodies remain idempotent no-ops with explanatory comments rather than actual `terraform state mv` invocations.

Classification counts re-confirmed at line 16–20: 39 `no-change` + 1 `deprecation-flagged` + 0 `attribute-edit-required` + 0 `state-mv-required`. No fabricated operations.

**Subtask 1.2 — `migrations/` directories absent before authoring**:
```
$ ls terraform/konnect-teams/migrations/ 2>/dev/null
$ ls .github/actions/provision-konnect-resources/terraform/migrations/ 2>/dev/null
$ # both silent — directories did not exist
```

**Subtask 1.3 — `.terraform/migrations-applied` already gitignored** (no `.gitignore` change needed):
```
$ git check-ignore -v terraform/konnect-teams/.terraform/migrations-applied
.gitignore:2:**/.terraform/*	terraform/konnect-teams/.terraform/migrations-applied
$ git check-ignore -v .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
.gitignore:2:**/.terraform/*	.github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
```

**Subtask 4.1 — Idempotency verification (outer tree, run from `terraform/konnect-teams/`)**:
```
=== OUTER tree run 1 ===
[migration 001] tree=terraform/konnect-teams: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
first run rc: 0
=== OUTER tree run 2 ===
[migration 001] tree=terraform/konnect-teams: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
second run rc: 0
```

**Subtask 4.1 — Idempotency verification (inner tree, run from `.github/actions/provision-konnect-resources/terraform/`)**:
```
=== INNER tree run 1 ===
[migration 001] tree=.github/actions/provision-konnect-resources/terraform: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
first run rc: 0
=== INNER tree run 2 ===
[migration 001] tree=.github/actions/provision-konnect-resources/terraform: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
second run rc: 0
```
Both trees: identical stderr line on each run, exit 0 twice, zero `state mv`/`state rm`/`import` invocations.

**Subtask 5.1 — Executable bit landed (mode `100755`):**
```
$ git ls-files --stage \
    terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh \
    .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh
100755 cdb836e2e79f93997f5ece4fafce7575d44591b0 0	.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh
100755 0219cff19aa6b2055e700fb11c473be2e7ed163e 0	terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh
```

**Subtask 5.2 / 5.3 — Diff scope (only the two new scripts + tracking files; `.gitignore` untouched):**
```
$ git status --short
A  .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh
 M _bmad-output/implementation-artifacts/sprint-status.yaml
A  terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh
?? _bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md

$ git diff --stat .gitignore
$ # empty — .gitignore not modified
```

**Subtask 5.4 — `shellcheck` not available on this host:**
```
$ which shellcheck
shellcheck not found
```
`shellcheck` is not installed in this environment, so the lint pass was skipped per the AC's "if available" qualifier. The scripts are intentionally minimal (shebang, `set -euo pipefail`, single-line `state_has` helper using `grep -Fxq --`, a commented template, one stderr `echo`) — no constructs that would trigger non-SC2317 findings.

### Completion Notes List

- **AC1 (paths + executable bit):** Both scripts created at the canonical P6 paths and committed with mode `100755` (verified via `git ls-files --stage`, see Debug Log §Subtask 5.1). Both `migrations/` directories were created in this PR (`mkdir -p`); neither existed before (Debug Log §Subtask 1.2). `core.fileMode` left untouched; `chmod +x` was sufficient on macOS.
- **AC2 (P6 header):** Both scripts open with `#!/usr/bin/env bash` then a comment block declaring Purpose ("Konnect provider state migration: 3.1.0 → 3.15.0"), Source provider version (`kong/konnect 3.1.0`), Target provider version (`kong/konnect 3.15.0`), Prerequisites (`terraform init -upgrade` already run + backend read access — with explicit note that this no-op body does not require an initialized backend), and the Idempotency note (re-runs are zero-op; every future `state mv`/`rm`/`import` will be guarded by `terraform state list | grep -Fxq`). The header references `_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md`. `set -euo pipefail` follows the header (line 35 in both files).
- **AC3 (body shape — no-op):** Each script body defines `state_has() { terraform state list | grep -Fxq -- "$1"; }` (`grep -Fx` per the spec — fixed-string, full-line match, with `--` to disarm any pattern that begins with `-`); contains the commented-out `terraform state mv` template; emits a single explanatory line to stderr identifying the tree; and exits 0 implicitly. No `terraform plan`/`apply`/`init` invocations. The `state_has` helper is intentionally not invoked from the no-op body, so the script does not require an initialized backend — verified by `bash` smoke-runs that succeeded without any prior `terraform init` (Debug Log §Subtask 4.1).
- **AC4 (idempotency by direct re-run):** Both scripts run twice in a row from each tree's root, exit 0 both times, emit identical stderr both times, perform zero state operations both times (Debug Log §Subtask 4.1).
- **AC5 (`terraform plan` parity — vacuous):** No live-state plan attempted; the script touches zero resources, so the plan-parity assertion is vacuously satisfied. Story 1.6 owns the live MinIO-backed verification.
- **AC6 (boundary discipline):** `git status --short` shows only the two new scripts plus the two tracking-file edits (this story file + `sprint-status.yaml`). No edits to `Makefile`, `MIGRATION.md` (still does not exist), `.gitignore`, any `*.tf` under either tree, any module under either tree, any `.github/workflows/*`, or any `action.yml`/`action.yaml`. No new files inside `migrations/` beyond the single script. No `README.md` inside either `migrations/`. (Debug Log §Subtask 5.2 / 5.3.)
- **AC7 (sprint status flip):** `_bmad-output/implementation-artifacts/sprint-status.yaml` updated: `1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees: ready-for-dev → in-progress → review`. Top-of-file comment updated and `last_updated` bumped to `"2026-05-10"`. STATUS DEFINITIONS block and all surrounding comments preserved. This story file's `Status:` flipped `ready-for-dev → in-progress → review`.

**Pre-known traps avoided** (per Dev Notes § Pre-known dev-agent traps):
- No fabricated `state mv` operations.
- No `make migrate-state` target added in this PR.
- No `MIGRATION.md` authored.
- No `.terraform/migrations-applied` writer logic in the script.
- No duplicate `.gitignore` rule.
- No `terraform init`/`plan`/`apply` invocation inside the script body.
- No `# shellcheck disable=` directives.
- No combining of the two scripts into a shared sourced helper.

**Anticipated `shellcheck` finding** (informational, since shellcheck was not run): the only callable code in the no-op body is the stderr `echo`; the `state_has` helper is defined-but-not-called by design. If a future contributor runs `shellcheck` against either script, the expected finding is SC2317 ("Command appears to be unreachable. Check usage…") on the helper. Per the story, this is the only acceptable finding and must not be silenced with a `disable` comment — it documents the intended future-proofing pattern.

### File List

**New files (mode 0755):**
- `terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh`
- `.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh`

**New directories (created implicitly by the new files above):**
- `terraform/konnect-teams/migrations/`
- `.github/actions/provision-konnect-resources/terraform/migrations/`

**Modified tracking files:**
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story key `1-4-…` flipped to `review`; `last_updated` bumped to 2026-05-10; comments preserved.
- `_bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md` — this file: status `ready-for-dev → review`, all task/subtask boxes ticked, Dev Agent Record populated.

### Review Findings

_Adversarial review on 2026-05-10 (Blind Hunter + Edge Case Hunter + Acceptance Auditor). All 7 ACs CONFIRMED by the Acceptance Auditor; no boundary violations, no P6 deviations, no cross-script drift beyond the documented `<TREE-IDENTIFIER>` substitution. The single substantive finding below concerns the latent semantics of the canonical `state_has` helper this story lands as the convention for migrations 002+._

- [x] [Review][Defer] Canonical `state_has` helper conflates real `terraform state list` failures with "address absent" — deferred to Story 1.5 driver: `make migrate-state` is the natural place to enforce `terraform init` + a `terraform state list` exit-0 precondition before invoking any migration script, matching the spec's separation between per-migration scripts (state-mutation contracts) and the driver (precondition gating). No code change in this PR. — Both scripts define `state_has() { terraform state list | grep -Fxq -- "$1"; }` ([`terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh:42-44`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh#L42-L44), [`.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh:42-44`](.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh#L42-L44)). When invoked inside the documented template `if state_has '<addr>'; then terraform state mv …; fi`, an uninitialized backend / lock contention / auth failure causes `terraform state list` to write `No state file was found!` to stderr and exit non-zero. Under `set -o pipefail` the pipeline returns non-zero, and inside the `if` `set -e` is suppressed, so the `if` branch is silently skipped — the migration no-ops on a tree that should have been migrated, and the subsequent `terraform apply` may then create resources at the new address while the old ones remain orphaned in state. The helper is unused on the 3.1.0 → 3.15.0 no-op path, so this story's body is unaffected; the issue is in the canonical pattern this PR establishes for migrations 002+. Spec deliberately mandates this exact helper shape (AC3, Dev Notes "Script template (canonical body)", and architecture P6); patching it is a contract decision, not an unambiguous fix. Options to consider: (a) accept as-is and let Story 1.5's `make migrate-state` driver enforce `terraform init` + `terraform state list` succeeds before invoking any migration script (preserves spec's body shape); (b) amend the helper to distinguish exit codes (e.g., `terraform state list >/tmp/state || return 2; grep -Fxq -- "$1" /tmp/state`) — deviates from spec, requires updating AC3 and the architecture P6 helper template; (c) leave as-is in this story and note for the Story 1.5/1.6 PR to harden via the driver. Recommended (a)+(c): driver-level enforcement is the natural home and matches the spec's separation between per-migration scripts (state-mutation contracts) and the driver (precondition gating).
