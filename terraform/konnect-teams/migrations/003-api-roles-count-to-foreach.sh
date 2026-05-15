#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Migration 003 — Refactor API/API Product role resources from count-indexed
#                 to for_each-indexed
#
# Purpose:
#   Maps the five old count-indexed konnect_system_account_role resources
#   (ap_creators, ap_viewers, api_creators, api_viewers, api_publishers) that
#   were driven by opaque konnect.api / konnect.api_product string entitlements
#   to the new for_each-indexed api_roles / api_product_roles resources driven
#   by the structured api_roles and api_product_roles YAML fields.
#
#   Without this migration, Terraform destroys the old resources and creates
#   identical new ones under different addresses, causing the same 409
#   "Resource Already Exists" race seen in migration 002.
#
# Address mapping (all with entity_id="*", region="eu" — what the old
# hardcoded resources used):
#
#   OLD (count-indexed)                          NEW (for_each-indexed)
#   konnect_system_account_role.api_creators[0]  api_roles["Creator-*-eu"]
#   konnect_system_account_role.api_viewers[0]   api_roles["Viewer-*-eu"]
#   konnect_system_account_role.api_publishers[0] api_roles["Publisher-*-eu"]
#   konnect_system_account_role.ap_creators[0]   api_product_roles["Creator-*-eu"]
#   konnect_system_account_role.ap_viewers[0]    api_product_roles["Viewer-*-eu"]
#
# Idempotency:
#   Every state mv is guarded by a state_has() precondition so the script is
#   safe to re-run. Teams where the old address is already absent are silently
#   skipped.
#
# Prerequisites:
#   - terraform init has been run in terraform/konnect-teams
#   - Backend credentials are available in the environment
# ------------------------------------------------------------------------------
set -euo pipefail

state_has() {
  terraform state list | grep -Fxq -- "$1"
}

teams=$(terraform state list \
  | grep -oE 'module\.system-account\["[^"]+"\]' \
  | sed 's/module\.system-account\["\(.*\)"\]/\1/' \
  | sort -u || true)

if [ -z "$teams" ]; then
  echo "[migration 003] no system-account modules found in state — nothing to do" >&2
  exit 0
fi

for team in $teams; do
  # api_creators[0] → api_roles["Creator-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.api_creators[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.api_roles["Creator-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 003] ${team}: mv api_creators[0] -> api_roles[\"Creator-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 003] ${team}: api_creators[0] not in state — skip" >&2
  fi

  # api_viewers[0] → api_roles["Viewer-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.api_viewers[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.api_roles["Viewer-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 003] ${team}: mv api_viewers[0] -> api_roles[\"Viewer-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 003] ${team}: api_viewers[0] not in state — skip" >&2
  fi

  # api_publishers[0] → api_roles["Publisher-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.api_publishers[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.api_roles["Publisher-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 003] ${team}: mv api_publishers[0] -> api_roles[\"Publisher-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 003] ${team}: api_publishers[0] not in state — skip" >&2
  fi

  # ap_creators[0] → api_product_roles["Creator-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.ap_creators[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.api_product_roles["Creator-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 003] ${team}: mv ap_creators[0] -> api_product_roles[\"Creator-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 003] ${team}: ap_creators[0] not in state — skip" >&2
  fi

  # ap_viewers[0] → api_product_roles["Viewer-*-eu"]
  old='module.system-account["'"${team}"'"].konnect_system_account_role.ap_viewers[0]'
  new='module.system-account["'"${team}"'"].konnect_system_account_role.api_product_roles["Viewer-*-eu"]'
  if state_has "${old}"; then
    echo "[migration 003] ${team}: mv ap_viewers[0] -> api_product_roles[\"Viewer-*-eu\"]" >&2
    terraform state mv "${old}" "${new}"
  else
    echo "[migration 003] ${team}: ap_viewers[0] not in state — skip" >&2
  fi
done

echo "[migration 003] done" >&2
