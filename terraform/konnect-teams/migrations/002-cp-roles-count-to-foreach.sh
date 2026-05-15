#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Migration 002 — Refactor CP role resources from count-indexed to for_each-indexed
#
# Purpose:
#   Maps the three old count-indexed konnect_system_account_role resources
#   (cp_creators, cp_viewers, cp_admins) that were driven by the opaque
#   konnect.control_plane / konnect.control_plane.admin string entitlements
#   to the new for_each-indexed cp_roles resource driven by the structured
#   control_plane_roles YAML field.
#
#   These resource renames would otherwise cause Terraform to destroy the
#   existing roles and recreate identical ones, which:
#     a) causes unnecessary churn in the Konnect API
#     b) races with the destroy on parallel apply, producing a 409
#        "Resource Already Exists" error if the API has not yet processed
#        the deletion when the create request arrives
#
# Address mapping (all with entity_id="*", region="eu", which is what the
# old hardcoded resources used):
#
#   OLD (count-indexed)                          NEW (for_each-indexed)
#   konnect_system_account_role.cp_creators[0]  cp_roles["Creator-*-eu"]
#   konnect_system_account_role.cp_viewers[0]   cp_roles["Viewer-*-eu"]
#   konnect_system_account_role.cp_admins[0]    cp_roles["Admin-*-eu"]
#
# Idempotency:
#   Every state mv is guarded by a state_has() precondition check so the
#   script is safe to re-run. Teams where the old address is already gone
#   (e.g. because a previous apply already destroyed+recreated them) are
#   silently skipped.
#
# Prerequisites:
#   - terraform init has been run in terraform/konnect-teams
#   - Backend credentials are available in the environment
# ------------------------------------------------------------------------------
set -euo pipefail

state_has() {
  terraform state list | grep -Fxq -- "$1"
}

# Discover all team names currently tracked in the state, e.g. "flight-operations"
teams=$(terraform state list \
  | grep -oE 'module\.system-account\["[^"]+"\]' \
  | sed 's/module\.system-account\["\(.*\)"\]/\1/' \
  | sort -u || true)

if [ -z "$teams" ]; then
  echo "[migration 002] no system-account modules found in state — nothing to do" >&2
  exit 0
fi

for team in $teams; do
  # Creator: cp_creators[0] → cp_roles["Creator-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.cp_creators[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.cp_roles["Creator-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 002] ${team}: mv cp_creators[0] -> cp_roles[\"Creator-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 002] ${team}: cp_creators[0] not in state — skip" >&2
  fi

  # Viewer: cp_viewers[0] → cp_roles["Viewer-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.cp_viewers[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.cp_roles["Viewer-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 002] ${team}: mv cp_viewers[0] -> cp_roles[\"Viewer-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 002] ${team}: cp_viewers[0] not in state — skip" >&2
  fi

  # Admin: cp_admins[0] → cp_roles["Admin-*-eu"]
  # This only existed for teams that had the konnect.control_plane.admin entitlement.
  old='module.system-account["'"${team}"'"].konnect_system_account_role.cp_admins[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.cp_roles["Admin-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 002] ${team}: mv cp_admins[0] -> cp_roles[\"Admin-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 002] ${team}: cp_admins[0] not in state — skip" >&2
  fi
done

echo "[migration 002] done" >&2
