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
  # Capture rc via `|| rc=$?` — `if ! cmd` would mask the real exit code (`!` resets $? to 0).
  rc=0
  (cd "$tree" && bash "migrations/$name") || rc=$?
  if [ "$rc" -ne 0 ]; then
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
