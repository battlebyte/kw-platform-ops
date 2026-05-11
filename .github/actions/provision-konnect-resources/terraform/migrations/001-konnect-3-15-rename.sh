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

echo "[migration 001] tree=.github/actions/provision-konnect-resources/terraform: no state operations required for kong/konnect 3.1.0 -> 3.15.0 (see _bmad-output/implementation-artifacts/1-1-konnect-3-15-audit.md)" >&2
