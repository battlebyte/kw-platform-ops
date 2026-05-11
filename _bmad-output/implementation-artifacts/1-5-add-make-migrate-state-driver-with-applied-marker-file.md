# Story 1.5: Add `make migrate-state` driver with applied-marker file

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a platform engineer,
I want a single `make migrate-state` target that discovers and runs unapplied `migrations/NNN-*.sh` scripts in both Terraform trees (outer first, inner second), records each applied script in a per-tree `.terraform/migrations-applied` marker file, and exits with a clear "no migrations pending" message on re-runs,
so that operators don't need to track which migrations have been applied or in which sequence, the driver provides the precondition gate that Story 1.4's `state_has` helper deliberately omits (deferred-work.md L20), and Story 1.6's clean-plan MinIO verification has a single canonical invocation to call.

This story is **driver-only**. It does **not** modify either [`migrations/001-konnect-3-15-rename.sh`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh) script (Story 1.4 owns; both are `done` and treated as a stable input contract). It does **not** author `MIGRATION.md` §2 (Story 1.6). It does **not** run a stateful `terraform plan` against MinIO or S3 (Story 1.6's gate). It does **not** edit `.gitignore` — `.terraform/migrations-applied` is already covered by `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2), as confirmed by Story 1.4 Subtask 1.3 (re-verify here, do **not** add a duplicate rule).

**Critical inputs from Story 1.4:**
- Both `migrations/001-konnect-3-15-rename.sh` scripts exist at the canonical P6 paths, mode `100755`, with `set -euo pipefail` and the documented header. They emit a single stderr line and exit 0 — re-runnable on any state (uninitialized backend OK for this hop's no-op body).
- Story 1.4 review surfaced a latent failure mode in the canonical `state_has` helper: under `pipefail`, a `terraform state list` failure (uninitialized backend, lock contention, auth) inside an `if state_has '<addr>'; then terraform state mv …; fi` block is silently swallowed by `set -e` suppression in `if`, causing the migration to no-op on a tree that should have been migrated. Story 1.4 deliberately did not patch this in-script (spec mandates the helper shape per architecture P6); the resolution path is **driver-level precondition gating** — verify each tree is initialized before invoking its migration scripts. This story is where that gate lands.

**Critical input from Architecture:**
- [`architecture.md:310-315`](_bmad-output/planning-artifacts/architecture.md#L310) (P6): driver invoked via `make migrate-state`, runs unapplied migrations in order, applied-marker at `.terraform/migrations-applied` (gitignored).
- [`architecture.md:576`](_bmad-output/planning-artifacts/architecture.md#L576): two-tree ordering — outer (`terraform/konnect-teams/`) first → inner (`.github/actions/provision-konnect-resources/terraform/`) second.
- [`architecture.md:475`](_bmad-output/planning-artifacts/architecture.md#L475): "Add `migrate-state` target | `Makefile` | D3, P6".

## Acceptance Criteria

1. **AC1 — `make migrate-state` target added to the top-level [`Makefile`](Makefile).**
   - New target named exactly `migrate-state` (no namespace, no prefix).
   - Help line follows the existing `## <description>` convention used by every other target in [`Makefile`](Makefile) (so `make help` lists it correctly).
   - Listed in the `.PHONY:` line at [`Makefile:51`](Makefile#L51) so it is not shadowed by a file/directory of the same name.
   - The target either inlines the driver logic *or* delegates to a single helper script under [`scripts/`](scripts/) — see AC2 for the helper-script decision and constraints.
   - Re-runnability is property-tested in AC6, not just declared in AC1.

2. **AC2 — Driver implemented as a helper script `scripts/run-migrations.sh` invoked by the Make target.**
   - The driver logic lives in [`scripts/run-migrations.sh`](scripts/run-migrations.sh) (new file, mode `0755`). Rationale: the existing `Makefile` consistently delegates non-trivial logic to `scripts/*.sh` (see [`Makefile:13`](Makefile#L13), [`:17`](Makefile#L17), [`:25`](Makefile#L25), [`:31`](Makefile#L31)). Keeping the driver out of `Makefile` recipe lines avoids `$$` quoting hell and preserves single-purpose helpers per project-context "File and folder organization."
   - The Make target invokes the helper once per Terraform tree, passing the tree's relative path as the sole positional argument: `./scripts/run-migrations.sh <tree>`. The Make target is responsible for ordering (outer first, inner second); the helper is per-tree and stateless across trees.
   - The helper begins with `#!/usr/bin/env bash` and `set -euo pipefail`, matching [`scripts/check-deps.sh`](scripts/check-deps.sh) / [`scripts/prep-actrc.sh`](scripts/prep-actrc.sh) discipline and project-context "Bash" rules.
   - The helper takes exactly one positional argument: the relative path to a Terraform tree root (e.g., `terraform/konnect-teams`). Validates the argument is non-empty and exists as a directory; otherwise exits non-zero with `usage:` to stderr.

3. **AC3 — Two-tree ordering: outer first, inner second.**
   - The Make target invokes the helper for [`terraform/konnect-teams`](terraform/konnect-teams) **first** (outer / platform-team tree).
   - The Make target invokes the helper for [`.github/actions/provision-konnect-resources/terraform`](.github/actions/provision-konnect-resources/terraform) **second** (inner / team-side tree).
   - Order is enforced by the target's recipe (e.g., a `for` loop over a hardcoded list, **or** two separate helper invocations). **Do not** discover trees dynamically (`find ... -name migrations -type d`) — the two-tree set is a stable architectural fact (per [`architecture.md#Two-Terraform-tree reality`](_bmad-output/planning-artifacts/architecture.md#L339)), and dynamic discovery invites drift if a third tree is added without an explicit story decision.
   - If the outer-tree invocation exits non-zero, the inner-tree invocation **does not** run and `make migrate-state` exits non-zero. This is the implicit behavior of `set -e` inside a Make recipe under `.SHELLFLAGS` defaults; verify in AC10.

4. **AC4 — Migration discovery (per tree).**
   - The helper discovers scripts matching the glob `<tree>/migrations/[0-9][0-9][0-9]-*.sh` and processes them in **lexicographic sorted order** (which is also chronological under the P6 zero-padded `NNN-` prefix convention).
   - Implementation: use `find <tree>/migrations -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.sh' | LC_ALL=C sort`. The `LC_ALL=C` locale pin guarantees deterministic ordering across operator machines (macOS / Linux locales sort differently otherwise). **Do not** use `ls migrations/*.sh` — when no matches exist, `ls` errors to stderr; the `find` form returns empty cleanly.
   - If `<tree>/migrations/` does not exist, the helper exits 0 with a one-line stderr note `[migrate-state] <tree>: no migrations/ directory, skipping`. Future-proofs the driver for trees that may not yet have a `migrations/` directory.
   - If `<tree>/migrations/` exists but is empty (no `[0-9][0-9][0-9]-*.sh` matches), behaves identically to "all already applied" (AC5) — the helper exits 0 with a one-line stderr note. No script execution.

5. **AC5 — Applied-marker file: `<tree>/.terraform/migrations-applied`.**
   - **Path:** literally `<tree>/.terraform/migrations-applied`, one file per tree.
   - **Format:** plain text, one applied-script **basename** per line (e.g., `001-konnect-3-15-rename.sh`). UTF-8, LF line endings, trailing newline after the last entry. No header, no comments, no timestamps, no script hashes — keep the format trivially diffable by `grep -Fxq -- "$name" <marker>` and trivially appendable by `>> <marker>`. (Format decisions deliberate; see Dev Notes "Applied-marker file format" for rationale.)
   - **Write timing:** after a script exits 0, the helper appends the basename to the marker file. **Per-script**, not batched at end of run — partial-failure leaves a partially-applied marker that correctly reflects what ran. Use `printf '%s\n' "$name" >> "$marker"` (atomic append on POSIX for short writes < `PIPE_BUF`).
   - **Read:** before invoking a script, the helper reads the marker (if it exists) and skips any script whose basename is already listed. Use `grep -Fxq -- "$name" "$marker"` to test membership (fixed-string, full-line, `--` to disarm leading-dash basenames). If the marker does not exist, treat as empty.
   - **Directory creation:** if `<tree>/.terraform/` does not exist (i.e., operator has not yet `terraform init`-ed this tree), the helper **does not** create it. Instead, AC7's precondition fires first and aborts before any script runs. Do **not** `mkdir -p <tree>/.terraform` from the driver — that would mask the missing-init failure mode, which is precisely the failure mode the driver is supposed to surface (see AC7 and Story 1.4 deferred-work item).
   - **Gitignore:** verified covered by `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2) per Story 1.4 Subtask 1.3. AC11 re-verifies with `git check-ignore -v`.

6. **AC6 — Idempotency: re-running with all migrations applied is a clean no-op exit 0 with a clear message.**
   - **Run 1 from a tree state where all migrations are applied** (marker file lists every `[0-9][0-9][0-9]-*.sh` in `migrations/`): the helper executes zero scripts, prints `[migrate-state] <tree>: no pending migrations (N already applied)` to stderr where `N` is the number of basenames in the marker, and exits 0.
   - **Run 2 (after run 1):** identical output, exit 0, marker file unchanged (byte-identical to before run 2).
   - **Top-level message:** the Make target also emits a final `[migrate-state] done.` line to stderr after both trees complete — so an operator running `make migrate-state` sees one terminal confirmation rather than just the per-tree stderr trail.

7. **AC7 — Precondition gate: tree must be initialized (`.terraform/` directory exists).**
   - Before processing any migration script in a tree, the helper verifies that `<tree>/.terraform/` exists. If absent, the helper exits non-zero with:
     ```
     ERROR: <tree>/.terraform/ does not exist. Run 'terraform init' in <tree> before 'make migrate-state'.
     ```
     to stderr. **Do not** run `terraform init` from the driver — backend selection (S3 vs. MinIO via `TF_BACKEND_CONFIG`, per architecture D1 / P1) and credential handling are operator decisions made before `make migrate-state` is invoked.
   - **Why this gate matters:** the canonical `state_has` helper landed by Story 1.4 ([`migrations/001-konnect-3-15-rename.sh:42-44`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh#L42)) — `terraform state list | grep -Fxq -- "$1"` — silently false-negates on uninitialized backends because `pipefail` makes the pipeline non-zero, then `set -e` is suppressed inside `if`, so the `if` branch is skipped and the migration no-ops on a tree that *should* have been migrated (deferred-work.md L20). Surfacing the failure at the driver gate, **before** any script body runs, is the resolution path the spec deliberately reserved for the driver (Story 1.4 deferred-work item; architecture P6 separation of "per-migration scripts = state-mutation contracts" vs. "driver = precondition gating").
   - **The 3.1.0 → 3.15.0 hop is exempt from the script-body side of this issue** — Story 1.4's 001 script is a no-op and intentionally does not invoke `state_has`. The driver gate still fires for it, because future migrations 002+ will invoke `state_has` and operators must learn the `terraform init` → `make migrate-state` sequencing now.
   - **Do not** additionally run `terraform state list` from the driver to verify it exits 0. That precondition is too strict — it would force the operator to have backend credentials at `make migrate-state` time, but for a tree with an empty state (legitimately, e.g., fresh local MinIO with no resources yet), `state list` returns "No state file was found!" and exits non-zero in some Terraform versions. The `.terraform/` directory existence check is the right granularity: it confirms the operator has done `terraform init`, without requiring live state.

8. **AC8 — Robust failure handling.**
   - If a migration script exits non-zero, the helper:
     - **Does not** append the script's basename to the marker file (the partial-failure marker correctly reflects what completed).
     - Prints `ERROR: <tree>: migration <name> failed with exit code <rc>` to stderr.
     - Exits with the same non-zero code as the failed script (preserves the original signal under `set -e` / `pipefail`).
   - The Make target's outer-then-inner sequencing means inner-tree migrations **do not** run if outer-tree migrations fail. This is the desired behavior — a half-migrated outer tree should block inner-tree migration to avoid two diverging state schemas.

9. **AC9 — Help line + `.PHONY` listing.**
   - Help line in [`Makefile`](Makefile) matches the existing pattern at [`Makefile:9`](Makefile#L9), [`:11`](Makefile#L11), [`:15`](Makefile#L15), etc. Suggested form (verify by running `make help` after the change):
     ```makefile
     migrate-state: ## Run pending Terraform state migrations in both trees (outer → inner)
     ```
   - `migrate-state` added to `.PHONY:` at [`Makefile:51`](Makefile#L51). The PHONY line currently reads `.PHONY: prepare actrc prep-act-secrets docker vault-secrets vault-pki clean stop check-deps test-validator`; append `migrate-state` at the end.
   - `make help` after the change must list `migrate-state` with its help text rendered correctly under the existing `awk` filter at [`Makefile:48`](Makefile#L48). The filter regex is `^[a-zA-Z_-]+:.*##` — `migrate-state` matches without modification.

10. **AC10 — Verification commands (operator-runnable, captured in Debug Log).**
    - **V1 — Help line renders:**
      ```bash
      make help | grep '^  migrate-state'
      ```
      Expected: one line like `  migrate-state   Run pending Terraform state migrations in both trees (outer → inner)`.
    - **V2 — Cold first run, both trees, with `.terraform/` already present in each tree** (operator pre-condition):
      ```bash
      # Prereq: terraform init -backend=false in both trees first (cheap, no creds)
      (cd terraform/konnect-teams && terraform init -backend=false -input=false -upgrade >/dev/null)
      (cd .github/actions/provision-konnect-resources/terraform && terraform init -backend=false -input=false -upgrade >/dev/null)
      rm -f terraform/konnect-teams/.terraform/migrations-applied \
            .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
      make migrate-state
      echo "rc=$?"
      cat terraform/konnect-teams/.terraform/migrations-applied
      cat .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
      ```
      Expected: rc=0; both marker files contain exactly `001-konnect-3-15-rename.sh\n`; outer-tree stderr line appears before inner-tree stderr line.
    - **V3 — Idempotent second run** (markers from V2 still present):
      ```bash
      make migrate-state
      echo "rc=$?"
      ```
      Expected: rc=0; stderr contains `no pending migrations (1 already applied)` for each tree; marker files unchanged (byte-identical to after V2 — verify with `sha256sum` if desired).
    - **V4 — Missing-init precondition fires:**
      ```bash
      rm -rf terraform/konnect-teams/.terraform
      make migrate-state
      echo "rc=$?"
      ```
      Expected: rc != 0; stderr contains `ERROR: terraform/konnect-teams/.terraform/ does not exist. Run 'terraform init' in terraform/konnect-teams before 'make migrate-state'.`; inner-tree helper is **not** invoked (no stderr from the inner-tree path).
    - **V5 — Outer-tree failure aborts inner-tree run** (synthetic failure injection — do NOT commit the temporary script):
      ```bash
      # SYNTHETIC: temporarily add an always-failing script to outer tree
      printf '#!/usr/bin/env bash\nexit 7\n' > terraform/konnect-teams/migrations/999-zz-synthetic-fail.sh
      chmod +x terraform/konnect-teams/migrations/999-zz-synthetic-fail.sh
      # Remove from outer marker so it's "pending"
      sed -i.bak '/999-zz-synthetic-fail.sh/d' terraform/konnect-teams/.terraform/migrations-applied 2>/dev/null || true
      make migrate-state; echo "rc=$?"
      # CLEANUP — required:
      rm -f terraform/konnect-teams/migrations/999-zz-synthetic-fail.sh
      rm -f terraform/konnect-teams/.terraform/migrations-applied.bak
      ```
      Expected: rc=7 (or non-zero matching `exit 7` from the synthetic script); inner-tree helper not invoked; outer-tree marker does **not** contain `999-zz-synthetic-fail.sh`. **Critical:** the cleanup `rm -f` of the synthetic script must run before any `git add`/commit — confirm with `git status` shows no `999-*` file before staging the PR.
    - All five verification command outputs captured verbatim in the Dev Agent Record § Debug Log References.

11. **AC11 — Boundary discipline (scope guardrails).**
    - **No edits** to either [`migrations/001-konnect-3-15-rename.sh`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh) (Story 1.4 owns; treat as stable input).
    - **No edits** to `MIGRATION.md` (Story 1.6 owns; the file does not yet exist — confirm with `ls MIGRATION.md` returning ENOENT).
    - **No edits** to [`.gitignore`](.gitignore) (covered by `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2); re-verify with `git check-ignore -v terraform/konnect-teams/.terraform/migrations-applied` and `git check-ignore -v .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied`; capture both lines in Debug Log).
    - **No edits** under `terraform/konnect-teams/*.tf`, `terraform/konnect-teams/modules/**`, `.github/actions/provision-konnect-resources/terraform/*.tf`, or `.github/actions/provision-konnect-resources/terraform/modules/**` (Stories 1.2 / 1.3 own those).
    - **No edits** to any [`.github/workflows/**`](.github/workflows/) or [`.github/actions/**/action.yml`](.github/actions/) / `action.yaml` (Epic 2 / 4 territory; `make migrate-state` is an operator-run command, not a workflow step).
    - **No new files** beyond [`scripts/run-migrations.sh`](scripts/run-migrations.sh) and this story's tracking files. No `README.md` inside `migrations/` (deferred per Story 1.4 AC6). No `scripts/README.md` (out of scope). No companion test script in `test/` (the AC10 verification commands are operator-runnable; no shell-test harness exists in this repo).
    - **No edits** to `docker-compose.yaml`, `webapp/`, `charts/`, `k8s/`, `konnect/`, `teams/`, `portal/`, `test/`.
    - `git diff --stat` after the work should show: `Makefile` (modified), `scripts/run-migrations.sh` (new), `_bmad-output/implementation-artifacts/sprint-status.yaml` (modified), and this story file (modified). **Nothing else.**

12. **AC12 — Sprint status updated.**
    - On story completion (after `dev-story` execution, pre-`code-review`), [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml) key `1-5-add-make-migrate-state-driver-with-applied-marker-file` moves `ready-for-dev` → `review` (the dev agent's `code-review` workflow advances to `done`). Bump `last_updated` to the current date. Preserve every other comment and the `STATUS DEFINITIONS` block.
    - This story file's `Status:` field at line 3 moves `ready-for-dev` → `in-progress` → `review` in step.

## Tasks / Subtasks

- [x] **Task 1: Confirm pre-conditions and scope inputs** (AC: 11)
  - [x] Subtask 1.1 — Re-read Story 1.4 dev-agent record sections "File List" and "Review Findings" in [`1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md`](_bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md). Confirm both `001-*.sh` scripts exist at their canonical paths, mode `100755`, and are byte-identical except for the `<TREE-IDENTIFIER>` substitution in the stderr line. Capture `git ls-files --stage` output for both paths in Debug Log.
  - [x] Subtask 1.2 — Verify [`MIGRATION.md`](MIGRATION.md) does **not** exist at repo root: `ls MIGRATION.md 2>/dev/null && echo "EXISTS — out of scope" || echo "absent (expected)"`. Capture in Debug Log.
  - [x] Subtask 1.3 — Confirm `.terraform/migrations-applied` is gitignored without a new rule (re-verify Story 1.4's Subtask 1.3):
    ```bash
    git check-ignore -v terraform/konnect-teams/.terraform/migrations-applied
    git check-ignore -v .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
    ```
    Expected: both return `.gitignore:2:**/.terraform/*\t<path>`. Capture both lines in Debug Log. **Do not** modify `.gitignore`.
  - [x] Subtask 1.4 — Read the current [`Makefile`](Makefile) end-to-end. Identify the precise insertion point for the new `migrate-state` target (recommended: after `test-validator` at [`Makefile:43-44`](Makefile#L43-L44), before the `help` target at [`Makefile:46`](Makefile#L46), so the target list reads logically). Confirm the `.PHONY:` line at [`Makefile:51`](Makefile#L51) is the single point of edit for the phony declaration.

- [x] **Task 2: Author `scripts/run-migrations.sh`** (AC: 2, 4, 5, 6, 7, 8)
  - [x] Subtask 2.1 — Create [`scripts/run-migrations.sh`](scripts/run-migrations.sh) using the canonical body in Dev Notes § "Driver template (canonical body)" below. Do **not** deviate without documenting why in Completion Notes — the template encodes every AC2–AC8 invariant.
  - [x] Subtask 2.2 — Make the script executable: `chmod +x scripts/run-migrations.sh`. Confirm `git ls-files --stage scripts/run-migrations.sh` shows `100755` after staging (matches the existing `scripts/*.sh` pattern — verify with `git ls-files --stage scripts/check-deps.sh`).
  - [x] Subtask 2.3 — Run `shellcheck scripts/run-migrations.sh` if available. Expected: zero findings. If `shellcheck` is unavailable, note in Debug Log and do not block; the AC10 verification runs are the functional gate.
  - [x] Subtask 2.4 — Smoke-run the helper against a temp directory with a controlled migration set (no real Terraform state involved) — see Dev Notes § "Standalone helper smoke-test recipe" for the exact recipe. This verifies AC4 (discovery), AC5 (marker read/write), AC6 (idempotency), AC7 (precondition gate), and AC8 (failure handling) **without** depending on the Make wiring landing first. Captures eight stderr lines in Debug Log.

- [x] **Task 3: Wire the `migrate-state` Make target** (AC: 1, 3, 9)
  - [x] Subtask 3.1 — Add the `migrate-state` target to [`Makefile`](Makefile) using the canonical recipe in Dev Notes § "Make target (canonical body)" below. Insertion point per Subtask 1.4.
  - [x] Subtask 3.2 — Append `migrate-state` to the `.PHONY:` line at [`Makefile:51`](Makefile#L51). Result:
    ```makefile
    .PHONY: prepare actrc prep-act-secrets docker vault-secrets vault-pki clean stop check-deps test-validator migrate-state
    ```
  - [x] Subtask 3.3 — Run `make help` and confirm the new target appears in the help output between `test-validator` and `help` (or in whatever position your insertion point dictates). Capture full `make help` output in Debug Log.

- [x] **Task 4: End-to-end verification** (AC: 6, 7, 8, 10)
  - [x] Subtask 4.1 — **V1** (AC10): `make help | grep '^  migrate-state'` returns one matching line. Capture in Debug Log.
  - [x] Subtask 4.2 — **V2** (AC10): cold run after `terraform init -backend=false` in both trees, with marker files removed. Both trees process their `001-*.sh`, marker files contain exactly the script basename. Outer-tree stderr appears before inner-tree stderr. Capture full command sequence and output in Debug Log.
  - [x] Subtask 4.3 — **V3** (AC10): idempotent second run. Both trees skip, exit 0, marker files byte-identical to V2 result. Capture `sha256sum` (or `shasum -a 256` on macOS) of both marker files before and after V3 in Debug Log to prove byte-equality.
  - [x] Subtask 4.4 — **V4** (AC10): remove `terraform/konnect-teams/.terraform/`, re-run, observe precondition error, observe inner-tree helper is **not** invoked (no inner-tree stderr). Capture in Debug Log.
  - [x] Subtask 4.5 — **V5** (AC10): synthetic-failure injection. **Critical:** confirm the synthetic script is fully removed before any `git add`. Capture in Debug Log:
    - The synthetic script creation command.
    - The `make migrate-state` failure output (exit code, error message).
    - The cleanup commands.
    - `git status --short` after cleanup — must show no `999-*` entry.
  - [x] Subtask 4.6 — Restore both trees to their post-V3 state for a clean PR: run `terraform init -backend=false -upgrade` in each tree, run `make migrate-state` once, confirm both marker files contain `001-konnect-3-15-rename.sh`. The marker files are gitignored (re-verified in Subtask 1.3) so they don't enter the diff — this is purely a state-restoration step to leave the working tree in a sensible state for review.

- [x] **Task 5: Scope and permission verification** (AC: 11)
  - [x] Subtask 5.1 — Confirm the executable bit landed on the helper:
    ```bash
    git ls-files --stage scripts/run-migrations.sh
    ```
    Expected: `100755 …` (matches `scripts/check-deps.sh` mode). If `100644`, run `git update-index --chmod=+x scripts/run-migrations.sh` and re-stage. **Do not** disable `core.fileMode` in this PR.
  - [x] Subtask 5.2 — Run `git diff --stat` against the merge base and confirm the diff contains **only**:
    - `Makefile` (modified — new target + `.PHONY` append; line-count delta ≈ +8 / -1).
    - `scripts/run-migrations.sh` (new; mode `0755`).
    - `_bmad-output/implementation-artifacts/sprint-status.yaml` (modified — story key flip + `last_updated`).
    - `_bmad-output/implementation-artifacts/1-5-add-make-migrate-state-driver-with-applied-marker-file.md` (this file — Status flip + Dev Agent Record).
    Anything else is a scope violation per AC11 — audit and revert before continuing.
  - [x] Subtask 5.3 — Confirm `.gitignore` is **not** in the diff: `git diff --stat .gitignore` returns empty. (AC11.)
  - [x] Subtask 5.4 — Confirm no synthetic-failure script leaked into the diff:
    ```bash
    git status --short | grep -E '999|synthetic' && echo "LEAK — clean up" || echo "clean"
    ```
    Expected: `clean`.

- [x] **Task 6: Story hand-off** (AC: 12)
  - [x] Subtask 6.1 — Update [`_bmad-output/implementation-artifacts/sprint-status.yaml`](_bmad-output/implementation-artifacts/sprint-status.yaml): the key `1-5-add-make-migrate-state-driver-with-applied-marker-file` flips `ready-for-dev` → `review`. Bump `last_updated` (top comment line 2 and `last_updated:` field at line 38). Preserve every other entry, every comment, the `STATUS DEFINITIONS` block, and the `WORKFLOW NOTES` block.
  - [x] Subtask 6.2 — Update this story's `Status:` field at line 3 from `ready-for-dev` → `review`.
  - [x] Subtask 6.3 — Tick every AC1–AC12 box in the PR description with file paths / command-output references (PR description is human-authored; AC1–AC12 verification captured in Completion Notes below).

## Dev Notes

### Why this story exists

Story 1.4 ([`done`](_bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md)) landed two `migrations/001-konnect-3-15-rename.sh` scripts following architecture pattern P6 ([`architecture.md:310-315`](_bmad-output/planning-artifacts/architecture.md#L310-L315)). P6 explicitly declares the driver contract:

> **Driver:** invoked via `make migrate-state`, which runs unapplied migrations in order. Applied marker file at `.terraform/migrations-applied` (gitignored).

This story is the implementation of that driver. After this story lands:
- Operators run `make migrate-state` once and the driver discovers + runs unapplied migrations in both trees in the correct order.
- Story 1.6 ([`epics.md#Story 1.6`](_bmad-output/planning-artifacts/epics.md#L346)) can then verify the clean-plan gate against a fresh MinIO backend by invoking `make migrate-state` as part of its procedure and authoring `MIGRATION.md` §2 to document the canonical operator sequence.
- Future provider bumps (002+, e.g., if `kong/konnect` moves to 4.x with real `state mv` operations) drop a new `NNN-*.sh` in each tree and the driver picks it up automatically — no `Makefile` edit needed.

### What this story does NOT do

- It does **not** modify either [`001-konnect-3-15-rename.sh`](terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh) (Story 1.4 done).
- It does **not** run `terraform init` from the driver. Backend selection (S3 vs. MinIO via `TF_BACKEND_CONFIG`, per [`architecture.md#P1`](_bmad-output/planning-artifacts/architecture.md#L246)) and credential handling are operator-driven; the driver only verifies post-init state (existence of `.terraform/`).
- It does **not** run `terraform state list` from the driver to verify state is reachable. That precondition is too strict — see AC7's "Do not additionally run `terraform state list`" note.
- It does **not** author [`MIGRATION.md`](MIGRATION.md) §2 (Story 1.6).
- It does **not** run a stateful `terraform plan` against MinIO or S3 (Story 1.6's gate).
- It does **not** modify [`.gitignore`](.gitignore) (`**/.terraform/*` already covers the marker — Story 1.4 confirmed at Subtask 1.3).
- It does **not** add a `README.md` inside either `migrations/` directory (deferred per Story 1.4 AC6).
- It does **not** create a workflow step that invokes `make migrate-state` in CI (Epic 4 / Epic 2 territory; the driver is an operator-run command per architecture P6).
- It does **not** rewrite the `state_has` helper in either `001-*.sh` (Story 1.4 deferred-work item L20 — the resolution is **driver-level gating** in this story, not in-script).
- It does **not** add `make migrate-state` as a dependency of `make prepare` ([`Makefile:9`](Makefile#L9)). `make prepare` is the local-stack bootstrap and runs on a freshly-cloned repo where there is no state to migrate; coupling them would force every cold-clone path through migration logic that has nothing to do for a fresh checkout.
- It does **not** introduce locale handling beyond `LC_ALL=C` on the `sort` invocation. The marker file is ASCII basenames; no Unicode concerns.

### Confirmed file inventory for this story

```
kw-platform-ops/
├── Makefile                           ← MODIFIED (new target + .PHONY append)
└── scripts/
    └── run-migrations.sh              ← NEW (mode 0755)
```

Plus the standard tracking files:
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (key flip + `last_updated` bump).
- `_bmad-output/implementation-artifacts/1-5-add-make-migrate-state-driver-with-applied-marker-file.md` (this file: tasks ticked, Dev Agent Record filled, Status → review).

**Total expected `git diff --stat` scope:** 1 modified `Makefile` + 1 new shell script + 2 tracking-file edits. **Nothing else.** AC11 enforces.

### Driver template (canonical body)

Use this template byte-for-byte for `scripts/run-migrations.sh`. The template encodes every AC2–AC8 invariant in one place; **do not** restructure into "helpers I made up" or "extracted functions for elegance" — the template is intentionally flat.

```bash
#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# scripts/run-migrations.sh — per-tree Terraform state-migration driver.
#
# Invoked by `make migrate-state` (top-level Makefile) once per Terraform tree.
# Discovers <tree>/migrations/[0-9][0-9][0-9]-*.sh, runs them in sorted order,
# and records each applied script's basename in <tree>/.terraform/migrations-applied
# (gitignored via **/.terraform/* at .gitignore:2).
#
# Per-script contract: scripts are pure state-mutation contracts (see
# architecture P6 and Story 1.4). The driver owns the precondition gate
# (.terraform/ must exist, i.e. `terraform init` was run) and the
# applied-marker bookkeeping. The script itself is responsible for
# idempotency within a single migration step.
#
# Usage: scripts/run-migrations.sh <tree-path>
# Example: scripts/run-migrations.sh terraform/konnect-teams
# ------------------------------------------------------------------------------
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: $0 <tree-path>" >&2
  exit 2
fi

tree="$1"

if [ ! -d "$tree" ]; then
  echo "ERROR: tree '$tree' is not a directory" >&2
  exit 2
fi

mig_dir="$tree/migrations"
marker="$tree/.terraform/migrations-applied"

# AC4: no migrations/ directory → nothing to do, exit clean.
if [ ! -d "$mig_dir" ]; then
  echo "[migrate-state] $tree: no migrations/ directory, skipping" >&2
  exit 0
fi

# AC7: precondition gate. The driver does NOT run `terraform init`; backend
# selection and credentials are operator decisions.
if [ ! -d "$tree/.terraform" ]; then
  echo "ERROR: $tree/.terraform/ does not exist. Run 'terraform init' in $tree before 'make migrate-state'." >&2
  exit 1
fi

# AC4: discover scripts deterministically. LC_ALL=C guarantees locale-stable sort.
scripts=()
while IFS= read -r f; do
  scripts+=("$f")
done < <(find "$mig_dir" -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.sh' | LC_ALL=C sort)

if [ "${#scripts[@]}" -eq 0 ]; then
  echo "[migrate-state] $tree: no migration scripts found, skipping" >&2
  exit 0
fi

# AC5: marker membership test uses fixed-string full-line match.
already_applied() {
  [ -f "$marker" ] && grep -Fxq -- "$1" "$marker"
}

applied_count=0
ran_count=0

for script in "${scripts[@]}"; do
  name="$(basename "$script")"
  if already_applied "$name"; then
    applied_count=$((applied_count + 1))
    continue
  fi
  echo "[migrate-state] $tree: running $name" >&2
  # AC8: run from the tree's root, in a subshell so cd doesn't leak.
  if ! (cd "$tree" && bash "migrations/$name"); then
    rc=$?
    echo "ERROR: $tree: migration $name failed with exit code $rc" >&2
    exit "$rc"
  fi
  # AC5: append-on-success, per-script.
  printf '%s\n' "$name" >> "$marker"
  echo "[migrate-state] $tree: marked $name applied" >&2
  ran_count=$((ran_count + 1))
done

# AC6: idempotent re-run message.
if [ "$ran_count" -eq 0 ]; then
  echo "[migrate-state] $tree: no pending migrations ($applied_count already applied)" >&2
else
  echo "[migrate-state] $tree: applied $ran_count migration(s)" >&2
fi
```

**Why each design choice:**
- `set -euo pipefail` — project-context "Bash" rule; uniformly applied across `scripts/*.sh`.
- `find … -maxdepth 1 -name '[0-9][0-9][0-9]-*.sh' | sort` rather than a shell glob — empty-glob safety (a globbed empty list returns the literal pattern under default Bash settings; `find` returns nothing).
- `LC_ALL=C sort` — deterministic across macOS / Linux.
- Subshell `(cd "$tree" && bash …)` rather than `pushd`/`popd` — atomic; the parent shell's CWD never changes; failure in the subshell doesn't strand state.
- `printf '%s\n'` rather than `echo` — `echo` interprets backslash escapes inconsistently across shells; `printf` is POSIX-stable.
- `printf >> "$marker"` — POSIX append is atomic for writes < `PIPE_BUF` (4096 bytes on Linux, 512 on macOS). A 40-byte basename + newline is well under both. No `flock` needed.
- Marker membership via `grep -Fxq -- "$name" "$marker"` rather than a shell loop — `grep -Fx` is fixed-string full-line; the `--` disarms basenames that begin with `-` (unlikely but cheap to defend).
- No locking / mutex — Make targets are operator-driven and single-threaded; concurrent `make migrate-state` invocations are not a contemplated use case.

### Make target (canonical body)

Insertion point: between `test-validator` ([`Makefile:43-44`](Makefile#L43-L44)) and `help` ([`Makefile:46`](Makefile#L46)).

```makefile
migrate-state: ## Run pending Terraform state migrations in both trees (outer → inner)
	@./scripts/run-migrations.sh terraform/konnect-teams
	@./scripts/run-migrations.sh .github/actions/provision-konnect-resources/terraform
	@echo "[migrate-state] done."
```

And the updated `.PHONY:` line (replace [`Makefile:51`](Makefile#L51)):

```makefile
.PHONY: prepare actrc prep-act-secrets docker vault-secrets vault-pki clean stop check-deps test-validator migrate-state
```

**Why each design choice:**
- Recipe lines prefixed with `@` — match existing-target pattern at [`Makefile:12-13`](Makefile#L12-L13), [`:16-17`](Makefile#L16-L17). Suppresses recipe echo; the helper script emits its own structured stderr.
- Outer-then-inner ordering hardcoded (two sequential recipe lines) — per AC3 rationale; no `for` loop, no dynamic discovery.
- Final `[migrate-state] done.` line — top-level AC6 confirmation; emitted only when both helper invocations exit 0 (Make's implicit `set -e` under `.SHELLFLAGS` defaults).
- No leading `@cd $(CURDIR)` — recipe lines start at repo root by default; both helper invocations use repo-relative paths, so this is correct.
- No `MAKEFLAGS += --no-print-directory` — recipe-level concern only; project's existing Makefile doesn't use it and `make help` already renders cleanly.

### Applied-marker file format

Decision: **plain text, one basename per line, LF-terminated, no header, no timestamps, no hashes.**

Alternatives considered:
- **JSON / YAML.** Rejected — requires `jq` / `yq` for read/write; both are installed-on-demand by composite actions ([`provision-konnect-resources/scripts/install-yq.sh`](.github/actions/provision-konnect-resources/scripts/install-yq.sh) pattern) but adding a hard dep for the driver is overkill. The marker is a private, machine-only artifact — human readability is a non-goal.
- **Per-line `<basename> <ISO-8601-timestamp>` records.** Rejected — `grep -Fxq` no longer suffices for membership test; timestamps add no signal to the "is this script applied?" question (operators can `stat` the file if they care when).
- **Per-line `<basename> <sha256-of-script-body>` records.** Rejected — would catch the case where a script body changes after being applied, but architecture P6 explicitly mandates idempotency: re-running an already-applied script is safe. The hash check would force a re-run if the body was tweaked, which is a different semantic from "re-runnable." Out of scope.

The trivial format chosen matches the established pattern in this repo's other state files (e.g., `act.secrets` is plain `KEY=value` per line, parsed with `grep -o '...=\K.*'`).

### Standalone helper smoke-test recipe (Subtask 2.4)

Use this recipe to exercise [`scripts/run-migrations.sh`](scripts/run-migrations.sh) against a controlled fixture **without** depending on real Terraform state. Captures every AC2–AC8 invariant. Run from repo root:

```bash
set -euo pipefail

# Setup
tmp=$(mktemp -d)
trap "rm -rf '$tmp'" EXIT
mkdir -p "$tmp/fake-tree/migrations" "$tmp/fake-tree/.terraform"

# Fixture: three migrations, one will fail in run 3.
printf '#!/usr/bin/env bash\necho "ran 001" >&2\n' > "$tmp/fake-tree/migrations/001-alpha.sh"
printf '#!/usr/bin/env bash\necho "ran 002" >&2\n' > "$tmp/fake-tree/migrations/002-beta.sh"
chmod +x "$tmp/fake-tree/migrations/"*.sh

echo "=== Smoke 1: cold run, two scripts pending ==="
./scripts/run-migrations.sh "$tmp/fake-tree"
echo "rc=$? marker=$(cat "$tmp/fake-tree/.terraform/migrations-applied")"

echo "=== Smoke 2: idempotent re-run ==="
./scripts/run-migrations.sh "$tmp/fake-tree"
echo "rc=$?"

echo "=== Smoke 3: new migration added, only it runs ==="
printf '#!/usr/bin/env bash\necho "ran 003" >&2\n' > "$tmp/fake-tree/migrations/003-gamma.sh"
chmod +x "$tmp/fake-tree/migrations/003-gamma.sh"
./scripts/run-migrations.sh "$tmp/fake-tree"
echo "rc=$? marker_lines=$(wc -l < "$tmp/fake-tree/.terraform/migrations-applied")"

echo "=== Smoke 4: failing migration aborts and is NOT marked ==="
printf '#!/usr/bin/env bash\nexit 5\n' > "$tmp/fake-tree/migrations/004-delta.sh"
chmod +x "$tmp/fake-tree/migrations/004-delta.sh"
./scripts/run-migrations.sh "$tmp/fake-tree" || echo "expected non-zero rc=$?"
grep -Fxq -- "004-delta.sh" "$tmp/fake-tree/.terraform/migrations-applied" && echo "BUG: failed migration was marked applied" || echo "OK: failed migration not marked"

echo "=== Smoke 5: missing .terraform/ aborts with clear message ==="
rm -rf "$tmp/fake-tree/.terraform"
./scripts/run-migrations.sh "$tmp/fake-tree" || echo "expected non-zero rc=$?"

echo "=== Smoke 6: no migrations/ directory exits clean ==="
mkdir -p "$tmp/no-migrations/.terraform"
./scripts/run-migrations.sh "$tmp/no-migrations"
echo "rc=$?"

echo "=== Smoke 7: empty migrations/ directory exits clean ==="
mkdir -p "$tmp/empty-migrations/.terraform" "$tmp/empty-migrations/migrations"
./scripts/run-migrations.sh "$tmp/empty-migrations"
echo "rc=$?"

echo "=== Smoke 8: bad usage exits 2 ==="
./scripts/run-migrations.sh || echo "expected rc=2 got rc=$?"
```

Capture all eight smoke-test outputs verbatim in the Dev Agent Record § Debug Log.

### Architecture compliance

From [`architecture.md`](_bmad-output/planning-artifacts/architecture.md):

- **D3 — Konnect Provider Migration** ([`architecture.md:177`](_bmad-output/planning-artifacts/architecture.md#L177)): the driver makes the per-tree migration scripts operator-invocable as a single command. The verification gate (clean plan against MinIO) is Story 1.6 — the driver is the **invocation** Story 1.6 will call.
- **P6 — Terraform state-migration script convention** ([`architecture.md:310-315`](_bmad-output/planning-artifacts/architecture.md#L310-L315)): "Driver: invoked via `make migrate-state`, which runs unapplied migrations in order. Applied marker file at `.terraform/migrations-applied` (gitignored)." Exact spec for this story.
- **Two-Terraform-tree reality** ([`architecture.md:339-345`](_bmad-output/planning-artifacts/architecture.md#L339-L345)): "D1, D3, P1, P6 apply identically to both [trees]." Driver invokes both trees; AC3 ordering is outer-first → inner-second per [`architecture.md#Nice-to-have:576`](_bmad-output/planning-artifacts/architecture.md#L576).
- **Anti-pattern: non-idempotent state-migration scripts** ([`architecture.md:334`](_bmad-output/planning-artifacts/architecture.md#L334)): "re-running on a clean checkout must succeed." AC6's re-run property is the driver-level expression of this anti-pattern guard.
- **Target tree** ([`architecture.md:354`](_bmad-output/planning-artifacts/architecture.md#L354)): "`Makefile` ← extended: `migrate-state` target". And [`architecture.md:475`](_bmad-output/planning-artifacts/architecture.md#L475): "**Add** `migrate-state` target | `Makefile` | D3, P6". This story closes the gap.
- **Gap Analysis** ([`architecture.md:572-576`](_bmad-output/planning-artifacts/architecture.md#L572-L576)): explicitly names "Migration applied-marker file format" (resolved here per Dev Notes § "Applied-marker file format") and "`make migrate-state` ordering across the two Terraform trees (outer first → inner)" (resolved here per AC3) as nice-to-have implementation decisions. This story is the resolution point for both gaps.

### Project context compliance

From [`_bmad-output/project-context.md`](_bmad-output/project-context.md):

- **Bash discipline** ([`project-context.md` Language-Specific Rules — Bash](_bmad-output/project-context.md)):
  - `set -euo pipefail` in `scripts/*.sh` — **enforced by AC2**.
  - OS detection via `uname -s` before downloading binaries — **not applicable** (the helper downloads nothing).
  - Never `echo` secrets — the helper emits only structured `[migrate-state] …` diagnostic lines; no secrets touched.
  - Detection of `bash` shell: not required for shebanged scripts; the `#!/usr/bin/env bash` line is sufficient.
- **File and folder organization** ([`project-context.md` Code Quality & Style Rules — File and folder organization](_bmad-output/project-context.md)):
  - `scripts/<helper>.sh` is the canonical location for repo-wide helper scripts. `run-migrations.sh` belongs here, **not** in either Terraform tree's `migrations/` directory (those are reserved for `NNN-*.sh` migration scripts per P6).
- **Naming conventions** ([`project-context.md` Naming conventions](_bmad-output/project-context.md)):
  - `scripts/run-migrations.sh` — kebab-case `.sh`, matches `check-deps.sh`, `prep-act-secrets.sh`, `vault-pki-setup.sh`. **Not** `migrate_state.sh` or `runMigrations.sh`.
  - The Make target name `migrate-state` is kebab-case, matches `make help` / `make test-validator` style.
- **Anti-patterns to avoid** ([`project-context.md` Critical Don't-Miss Rules — Anti-patterns to avoid](_bmad-output/project-context.md)):
  - "❌ Adding `continue-on-error: true` or `|| true` to validators, linters, or `terraform plan/apply` steps." The driver does **not** add `|| true` anywhere; `set -e` plus explicit failure handling in AC8 is the right shape.
  - "❌ Echoing secrets to logs." Driver emits structured `[migrate-state] …` text; no secrets surfaced.
- **No inline comments unless the why is non-obvious.** The driver template's header comment is non-obvious (declares the per-script-contract / driver-precondition-gate separation); keep. The brief per-section inline comments tied to AC numbers are non-obvious in absence of this story file; keep. Do **not** add explanatory comments around `set -euo pipefail` or trivial control flow.

### Carryover from prior stories

**Story 1.1 (audit, [`done`](_bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)):**
- Operation count = 0 for the 3.1.0 → 3.15.0 hop. The driver runs Story 1.4's no-op script bodies — this story does not depend on real `terraform state mv` operations existing.

**Story 1.2 (outer-tree HCL bump, [`done`](_bmad-output/implementation-artifacts/1-2-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-terraform-konnect-teams.md)):**
- Outer tree pinned at `kong/konnect = 3.15.0` exact. The driver's V2/V3 verification (AC10) requires `terraform init -backend=false` to succeed in the outer tree — the bump is what makes the 3.15.0 provider plugin downloadable. No driver-side action needed; Story 1.2 is the input.

**Story 1.3 (inner-tree HCL bump, [`done`](_bmad-output/implementation-artifacts/1-3-bump-konnect-provider-to-3-15-and-apply-schema-updates-in-github-actions-provision-konnect-resources-terraform.md)):**
- Inner tree pinned at `kong/konnect = 3.15.0` exact across root + 39 modules. Same: makes inner-tree `terraform init -backend=false` succeed so AC10 V2/V3 can run.
- The Story 1.3 deferred-work flag at [`main.tf:95`](.github/actions/provision-konnect-resources/terraform/main.tf#L95) (`data.terracurl_request.fetch_team` unguarded for refresh-less plan) **does not affect this story** — the driver does not run `terraform plan`; it only requires `.terraform/` exists. `terraform init -backend=false` is sufficient to create that directory.

**Story 1.4 (migration scripts, [`done`](_bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md)):**
- Both `001-konnect-3-15-rename.sh` scripts at canonical P6 paths, mode `100755`, no-op bodies that emit one stderr line and exit 0. **Treat as stable input contract — do not modify.**
- Review found the canonical `state_has` helper conflates real `terraform state list` failures with "address absent" ([deferred-work.md L20](_bmad-output/implementation-artifacts/deferred-work.md#L20)). The deferred resolution path is: **driver runs `terraform init` and verifies `terraform state list` exits 0 before invoking any migration script.** This story implements a *narrower* gate: verify `.terraform/` exists (operator has `init`-ed) but **do not** run `terraform state list` (too strict — see AC7 "Do not additionally run `terraform state list`"). The narrower gate is sufficient to surface the missing-init failure mode at the driver before any `state_has` invocation can silently false-negate. Future-tightening (e.g., run `state list` for trees with non-no-op migration bodies) is deferred to whatever story lands the first non-no-op migration body (i.e., the first 002+ migration).
- `.terraform/migrations-applied` is gitignored via `**/.terraform/*` at [`.gitignore:2`](.gitignore#L2). Story 1.4 confirmed; AC11 + Subtask 1.3 re-confirm in this story. **Do not** add a duplicate rule.

**Pattern across 1.1 / 1.2 / 1.3 / 1.4:** every story keeps its `git diff --stat` scope tight to what its ACs name. Resist the urge to fix unrelated rot in this PR — AC11 enforces a 4-file diff limit.

### Pre-known dev-agent traps

The dev agent for this story is at risk of several specific over-implementation patterns. Each is named here so the implementation stays narrow.

- **Reinventing a Make-style driver.** This is a 30-line driver in `bash`. Do not pull in a migration library (`go-migrate`, Alembic-like tooling, `tern`, etc.). The repo has no Python runtime beyond the Flask webapp and no Go toolchain. Bash + `find` + `grep -Fxq` is the right tool here.
- **Adding migration *down* / rollback support.** Out of scope. P6 specifies forward-only migrations; rollback semantics for Terraform state are usually wrong (state goes forward; downgrade-the-provider is operator-driven and lives in `MIGRATION.md` §2's downgrade-path section, Story 1.6). Do **not** add a `make rollback-state` target or per-script down counterparts.
- **Running `terraform init` from inside the driver.** Don't. Backend selection and credential handling are operator decisions. The driver's contract is "given a tree the operator has already `init`-ed, run pending migrations." See AC7.
- **Running `terraform state list` to verify state is reachable.** Don't (in this story). The 3.1.0 → 3.15.0 no-op body doesn't need it, and the precondition is too strict for trees with legitimately empty state. The narrower `.terraform/` existence check is what AC7 mandates.
- **Discovering trees dynamically** (e.g., `find . -name migrations -type d` or `find terraform .github/actions -name migrations -type d`). Don't — the two-tree set is a stable architectural fact per [`architecture.md#Two-Terraform-tree reality`](_bmad-output/planning-artifacts/architecture.md#L339); dynamic discovery invites drift. Hardcode the two paths in the Make target.
- **Locking / mutex / per-tree concurrency.** Don't. Make targets are single-threaded operator runs; concurrent `make migrate-state` invocations are not a contemplated use case.
- **Embedding the driver in the `Makefile` recipe directly** (multi-line shell with `$$`-quoting hell). Don't — the repo's convention is to delegate to `scripts/*.sh`. See [`Makefile:13`](Makefile#L13), [`:17`](Makefile#L17), [`:25`](Makefile#L25), [`:31`](Makefile#L31).
- **Adding the driver as a CI workflow step.** Don't (in this story). `make migrate-state` is operator-invoked per architecture P6. A future workflow (Epic 4 territory) may invoke it inside a Terraform-touching workflow, but that is not this story.
- **Coupling `migrate-state` to `make prepare`.** Don't — `make prepare` runs on a freshly-cloned repo with no state to migrate. Adding `migrate-state` as a `prepare` dependency forces every cold-clone path through migration logic that has nothing to do.
- **Marker file in a non-gitignored location.** Don't change the path. `<tree>/.terraform/migrations-applied` is gitignored via the existing `**/.terraform/*` rule. Any other location (e.g., `<tree>/migrations/.applied` or repo-root `.migrations-applied`) would require a new `.gitignore` rule and break AC11.
- **Marker file with timestamps / JSON / YAML.** Don't — see Dev Notes § "Applied-marker file format" for the rejected alternatives and the rationale for plain `<basename>\n` lines.
- **Authoring `MIGRATION.md` §2 "while we're here."** Don't — Story 1.6 owns. The driver's contract makes Story 1.6 trivial to author; that's the right separation.
- **Modifying `001-konnect-3-15-rename.sh` to invoke `terraform state list` for a "real" precondition demo.** Don't — Story 1.4 deliberately landed the no-op body; modifying it here re-opens a closed story scope and AC11 forbids.
- **Adding `shellcheck` to CI in this PR.** Out of scope. Optional locally (Subtask 2.3) if available. Production `shellcheck` enforcement is Epic 4 (lint workflows) territory.

### Testing standards

This story produces a Bash driver script + a Make target. No unit-test framework involved (repo has none for shell). The "tests" are mechanical:

1. **Static gate (this story's gate):**
   - `scripts/run-migrations.sh` has mode `0755`, the canonical body, `set -euo pipefail`, `#!/usr/bin/env bash` shebang.
   - `shellcheck scripts/run-migrations.sh` clean (Subtask 2.3) **if** shellcheck is available — Story 1.4 ran in an environment without shellcheck; same posture here.
   - `Makefile` syntax: `make -n migrate-state` from a clean checkout runs without error (dry-run).
2. **Standalone smoke test (this story's gate, Subtask 2.4):** the eight-scenario fixture in Dev Notes § "Standalone helper smoke-test recipe" covers AC4 / AC5 / AC6 / AC7 / AC8 without touching real Terraform state.
3. **End-to-end verification (this story's gate, AC10):** V1–V5 against both real Terraform trees with `terraform init -backend=false`.
4. **Live-state plan gate (Story 1.6's gate):** `terraform plan` against MinIO local backend after `make migrate-state` shows zero diffs in both trees. **Out of scope here.**

### Project Structure Notes

- This story file goes in [`_bmad-output/implementation-artifacts/`](_bmad-output/implementation-artifacts/) (sibling to Stories 1.1–1.4). Same pattern as every prior Epic-1 story.
- `scripts/run-migrations.sh` colocates with the other repo-wide helpers in [`scripts/`](scripts/) (`check-deps.sh`, `prep-actrc.sh`, `prep-act-secrets.sh`, etc.). Single-purpose convention per [`project-context.md#File and folder organization`](_bmad-output/project-context.md).
- `Makefile` modification is targeted (one new target, one `.PHONY` append, ~6 line-count delta).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.5] — BDD acceptance criteria (epic file).
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1] — Epic 1 goal and FR/NFR coverage (FR33 owned here).
- [Source: _bmad-output/planning-artifacts/architecture.md#D3 — Konnect Provider Migration (3.1.0 → 3.15)] — migration decision; the driver is the operator-side invocation Story 1.6 will call.
- [Source: _bmad-output/planning-artifacts/architecture.md#P6 — Terraform state-migration script convention] — exact driver contract: `make migrate-state`, applied marker at `.terraform/migrations-applied` (gitignored).
- [Source: _bmad-output/planning-artifacts/architecture.md#Two-Terraform-tree reality] — two-tree set is architectural; driver hardcodes the two paths.
- [Source: _bmad-output/planning-artifacts/architecture.md#Decision Impact Analysis] — implementation sequence places D3 first.
- [Source: _bmad-output/planning-artifacts/architecture.md#Anti-patterns specific to this architecture] — "non-idempotent state-migration scripts" anti-pattern; AC6 is the driver-level guard.
- [Source: _bmad-output/planning-artifacts/architecture.md#Gap Analysis Results] — names "Migration applied-marker file format" and "`make migrate-state` ordering across the two Terraform trees" as nice-to-haves resolved by this story.
- [Source: _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md] — Story 1.1 deliverable; informational only (the driver does not consume the audit directly).
- [Source: _bmad-output/implementation-artifacts/1-4-implement-idempotent-001-konnect-3-15-rename-sh-state-migration-scripts-in-both-terraform-trees.md] — Story 1.4 done; provides the migration scripts the driver invokes.
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — L20: Story 1.4 review item resolved by AC7 (driver-level precondition gate).
- [Source: _bmad-output/project-context.md#Bash (in composite actions and scripts)] — `set -euo pipefail` discipline.
- [Source: _bmad-output/project-context.md#File and folder organization] — `scripts/<helper>.sh` location.
- [Source: _bmad-output/project-context.md#Anti-patterns to avoid] — `|| true` / `continue-on-error` prohibition.
- [Source: Makefile] — current top-level targets; insertion point and `.PHONY` line.
- [Source: .gitignore#L2] — `**/.terraform/*` covers `.terraform/migrations-applied` without a new rule.
- [Source: terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh] — Story 1.4 outer-tree script (treat as stable input).
- [Source: .github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh] — Story 1.4 inner-tree script (treat as stable input).

## Dev Agent Record

### Agent Model Used

claude-opus-4-7 (1M context) via Claude Code (`bmad-dev-story` skill).

### Debug Log References

**Subtask 1.1 — `git ls-files --stage` for both 001 scripts:**
```
100755 cdb836e2e79f93997f5ece4fafce7575d44591b0 0	.github/actions/provision-konnect-resources/terraform/migrations/001-konnect-3-15-rename.sh
100755 0219cff19aa6b2055e700fb11c473be2e7ed163e 0	terraform/konnect-teams/migrations/001-konnect-3-15-rename.sh
```

**Subtask 1.2 — `ls MIGRATION.md`:** `absent (expected)`.

**Subtask 1.3 — `git check-ignore -v` for both marker paths:**
```
.gitignore:2:**/.terraform/*	terraform/konnect-teams/.terraform/migrations-applied
.gitignore:2:**/.terraform/*	.github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
```

**Subtask 1.4 — Makefile insertion point:** between `test-validator:` (ending line 44) and `help:` (was line 46), and `.PHONY:` line at line 51 — confirmed end-to-end read.

**Subtask 2.2 — `git ls-files --stage scripts/run-migrations.sh`:**
```
100755 e69de29b... 0	scripts/run-migrations.sh
```
Mode matches `scripts/check-deps.sh` (`100755`).

**Subtask 2.3 — `shellcheck scripts/run-migrations.sh`:** clean (zero findings).

**Subtask 2.4 — Standalone helper smoke-test (8 scenarios):** all eight scenarios passed. Scenario 4 surfaced a latent template bug (see Completion Notes "Template deviation"); fix verified by an extra run that captured `rc=5` from a synthetic `exit 5` script and reported `failed with exit code 5` in the error line.

**Subtask 3.3 — `make help`:**
```
Available targets:

Usage:
  make <target>

  prepare          Prepare the project
  actrc            Setup .actrc
  prep-act-secrets  Prepare secrets
  docker           Spin up docker containers
  vault-pki        Setup vault pki
  check-deps       Check dependencies
  stop             Stop all containers
  clean            Clean everything up
  test-validator   Run provisioner manifest validation checks
  migrate-state    Run pending Terraform state migrations in both trees (outer → inner)
  help             Show this help
```

**Subtask 4.1 — V1 (`make help | grep '^  migrate-state'`):**
```
  migrate-state    Run pending Terraform state migrations in both trees (outer → inner)
```

**Subtask 4.2 — V2 (cold first run):**
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
rc=0
```
Both marker files contained exactly `001-konnect-3-15-rename.sh\n`. Outer-tree stderr precedes inner-tree stderr.

**Subtask 4.3 — V3 (idempotent re-run) sha256 before/after:**
```
pre-V3:
b8b79e8c13734177300e7ef95c03d3cc7de60283aa770c630418e8dcc17d38dd  terraform/konnect-teams/.terraform/migrations-applied
b8b79e8c13734177300e7ef95c03d3cc7de60283aa770c630418e8dcc17d38dd  .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied

V3 output:
[migrate-state] terraform/konnect-teams: no pending migrations (1 already applied)
[migrate-state] .github/actions/provision-konnect-resources/terraform: no pending migrations (1 already applied)
[migrate-state] done.
rc=0

post-V3 (byte-identical):
b8b79e8c13734177300e7ef95c03d3cc7de60283aa770c630418e8dcc17d38dd  terraform/konnect-teams/.terraform/migrations-applied
b8b79e8c13734177300e7ef95c03d3cc7de60283aa770c630418e8dcc17d38dd  .github/actions/provision-konnect-resources/terraform/.terraform/migrations-applied
```

**Subtask 4.4 — V4 (missing-init precondition):**
```
ERROR: terraform/konnect-teams/.terraform/ does not exist. Run 'terraform init' in terraform/konnect-teams before 'make migrate-state'.
make: *** [migrate-state] Error 1
rc=2
```
Inner-tree helper not invoked (no inner-tree stderr line). `make` exited Error 1 (helper rc=1); shell `$?` for the chained command was 2 — i.e., non-zero as AC10 V4 requires.

**Subtask 4.5 — V5 (synthetic failure injection):**
- Creation: `printf '#!/usr/bin/env bash\nexit 7\n' > terraform/konnect-teams/migrations/999-zz-synthetic-fail.sh && chmod +x ...`
- Output:
  ```
  [migrate-state] terraform/konnect-teams: running 001-konnect-3-15-rename.sh
  [migration 001] tree=terraform/konnect-teams: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)
  [migrate-state] terraform/konnect-teams: marked 001-konnect-3-15-rename.sh applied
  [migrate-state] terraform/konnect-teams: running 999-zz-synthetic-fail.sh
  ERROR: terraform/konnect-teams: migration 999-zz-synthetic-fail.sh failed with exit code 7
  make: *** [migrate-state] Error 7
  rc=2
  ```
- Outer marker post-failure: contains only `001-konnect-3-15-rename.sh` — `999-zz-synthetic-fail.sh` is NOT marked. Inner-tree helper not invoked.
- Cleanup: `rm -f terraform/konnect-teams/migrations/999-zz-synthetic-fail.sh` and `rm -f terraform/konnect-teams/.terraform/migrations-applied.bak`.
- `git status --short` after cleanup: only `Makefile`, `sprint-status.yaml`, the story file, and `scripts/run-migrations.sh` listed — no `999-*` leak.

**Subtask 4.6 — Final clean state-restore run:**
```
[migrate-state] terraform/konnect-teams: no pending migrations (1 already applied)
[migrate-state] .github/actions/provision-konnect-resources/terraform: no pending migrations (1 already applied)
[migrate-state] done.
rc=0
```

**Subtask 5.1 — `git ls-files --stage scripts/run-migrations.sh`:** mode `100755` confirmed.

**Subtask 5.2 — `git diff --stat HEAD`:**
```
 Makefile                                           |  7 +-
 _bmad-output/implementation-artifacts/sprint-status.yaml    |  6 +-
 scripts/run-migrations.sh                          | 94 ++++++++++++++++++++++
```
Plus the untracked story file itself. Total: 4 files, exactly matching AC11.

**Subtask 5.3 — `git diff --stat HEAD -- .gitignore`:** empty (no changes to `.gitignore`).

**Subtask 5.4 — Synthetic-leak check:** `clean`.

### Completion Notes List

- **Template deviation (documented per Subtask 2.1 contract):** the canonical body in Dev Notes § "Driver template (canonical body)" used `if ! (cd "$tree" && bash …); then rc=$?; …; exit "$rc"; fi`. Under POSIX shell semantics, `!` inverts the exit status and resets `$?` inside the then-branch to `0`, so the original migration-script exit code is lost — `rc` was always `0` and `exit "$rc"` would have exited 0 on failure, violating AC8 ("Exits with the same non-zero code as the failed script"). Surfaced by Smoke 4 (synthetic `exit 5` reported as `failed with exit code 0`). Replaced the construct with `rc=0; (cd "$tree" && bash "migrations/$name") || rc=$?; if [ "$rc" -ne 0 ]; then …; exit "$rc"; fi`. Confirmed: a synthetic `exit 5` now reports `failed with exit code 5` and the helper exits 5; V5 confirmed `exit 7` propagates end-to-end (`make: *** [migrate-state] Error 7`). Every other line of the template is byte-for-byte from Dev Notes.
- **AC1 (Make target):** added between `test-validator` and `help`; phony entry appended at end of `.PHONY` line.
- **AC2 (helper script):** `scripts/run-migrations.sh` created, mode `100755`, `set -euo pipefail`, shellcheck clean.
- **AC3 (two-tree ordering):** hardcoded — outer (`terraform/konnect-teams`) first, inner (`.github/actions/provision-konnect-resources/terraform`) second; no dynamic discovery.
- **AC4 (discovery):** `find <tree>/migrations -maxdepth 1 -type f -name '[0-9][0-9][0-9]-*.sh' | LC_ALL=C sort`.
- **AC5 (marker format):** `<tree>/.terraform/migrations-applied`, plain basenames, LF-terminated, append-on-success.
- **AC6 (idempotency):** V3 verified byte-identical markers via sha256; per-tree `no pending migrations (1 already applied)` stderr line; top-level `[migrate-state] done.` line.
- **AC7 (precondition gate):** V4 verified — missing `.terraform/` aborts with the documented message; inner-tree not invoked.
- **AC8 (failure handling):** V5 verified — `exit 7` propagated; failed-script basename not appended; inner-tree not invoked.
- **AC9 (help line + .PHONY):** `make help` shows the new target correctly under the existing awk filter.
- **AC10 (V1–V5):** all five captured above.
- **AC11 (scope):** 4-file diff exactly (`Makefile`, `scripts/run-migrations.sh`, `sprint-status.yaml`, this story file); `.gitignore` untouched; no synthetic-script leak.
- **AC12 (sprint status):** flipped `1-5-…` from `ready-for-dev` → `in-progress` at start of run, then to `review` at hand-off (this commit); `last_updated` bumped to `2026-05-11`; story `Status:` flipped to `review`; STATUS DEFINITIONS / WORKFLOW NOTES blocks and all other entries preserved.

### File List

- `Makefile` — modified (added `migrate-state` target between `test-validator` and `help`; appended `migrate-state` to `.PHONY:` line)
- `scripts/run-migrations.sh` — new, mode `0755`
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — modified (story key `ready-for-dev` → `in-progress` → `review`; `last_updated` bumped)
- `_bmad-output/implementation-artifacts/1-5-add-make-migrate-state-driver-with-applied-marker-file.md` — modified (Status flipped, all task/subtask boxes ticked, Dev Agent Record + Change Log filled)

### Change Log

- 2026-05-11 — Story 1.5 implementation: added `make migrate-state` driver with per-tree applied-marker file at `<tree>/.terraform/migrations-applied`. New helper `scripts/run-migrations.sh` enforces precondition (`.terraform/` must exist), discovers `migrations/NNN-*.sh` deterministically (`LC_ALL=C sort`), skips already-applied scripts via fixed-string full-line marker lookup, appends per-script on success, and propagates failing-script exit codes. V1–V5 captured in Debug Log; scope held to four files per AC11. Template deviation from Dev Notes § "Driver template (canonical body)" documented in Completion Notes (`if ! cmd; then rc=$?` masks original exit code under `!` semantics; replaced with `|| rc=$?` capture).

### Review Findings

**Adversarial code review (2026-05-11) — three parallel layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor.**

Outcome: **0 decision-needed, 0 patch, 5 defer, ~17 dismissed.** No AC violations found. Acceptance Auditor confirms the implementation matches the spec faithfully, the documented template deviation is correct, and scope is held to the four files AC11 requires. The five deferred items are edge-cases tolerated by the per-script idempotency contract or by the single-operator design — none block the story; all are tracked in `deferred-work.md`.

- [x] [Review][Defer] Non-atomic marker append on SIGINT [scripts/run-migrations.sh:84] — if the process is killed between successful migration body and `printf >> "$marker"`, the migration is applied but unmarked, so the next run re-executes it. Per-script idempotency contract (script header) is the safety net. Future hardening: write via temp+`mv` or trap signals around the critical section.
- [x] [Review][Defer] No concurrency lock on marker file [scripts/run-migrations.sh:78-84] — two parallel `make migrate-state` invocations could both observe a migration as unapplied, both execute it, and both append duplicate marker entries. The Terraform backend usually has its own lock; the driver does not. Single-operator design is intentional per spec but undocumented in the script header.
- [x] [Review][Defer] Marker tolerance: CRLF endings and trailing whitespace cause re-execution [scripts/run-migrations.sh:62] — `grep -Fxq` requires exact full-line match. A hand-edited or CRLF-normalised marker silently fails the membership test, the migration re-runs, and the marker gets duplicate entries. Low likelihood in practice (marker is gitignored, machine-written) but no guard exists.
- [x] [Review][Defer] `find` exit code not propagated in process substitution [scripts/run-migrations.sh:50-53] — under `< <(find ... | sort)`, only `sort`'s exit code matters; a `find` permission error would silently yield an empty list ("no migration scripts found, skipping") in a tree that actually has migrations. Rare with `-maxdepth 1` on a small directory.
- [x] [Review][Defer] Driver exit codes 1 and 2 collide with arbitrary migration-script exit codes [scripts/run-migrations.sh:21,28,46,88] — a caller cannot distinguish "driver rejected input" (rc=2 bad args / not-a-dir, rc=1 missing `.terraform/`) from "migration body returned 1 or 2." Acceptable today; worth a documented convention if future migrations want richer signaling.

Dismissed as noise/intentional/out-of-scope (not enumerated individually; full triage in code-review session transcript): arithmetic-postfix `set -e` false positive; `LC_ALL=C` correctness; basename newline-safety foreclosed by glob; `[migrate-state] done.` success-gated UX; absence of `check-deps` prerequisite; pre-existing `%-15s` awk width drift; intentional `bash <file>` invocation bypassing exec bit; intentional gitignored marker (architecture P6); deliberate stdout/stderr split; trailing-slash tree path cosmetics; `-h`/`--help` UX (would deviate from byte-for-byte canonical body); broken-symlink in `migrations/` (deployment error); `.SHELLFLAGS` not introduced (project doesn't use it); `.PHONY` non-issue; `REPO_ROOT` env contract (future-migration concern, not bug); two textual self-inconsistencies inside the spec (spec-author concern, not implementation).
