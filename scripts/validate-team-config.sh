#!/usr/bin/env bash
# Usage: validate-team-config.sh <config-dir>
# Validates all *.yaml / *.yml team config files in <config-dir>.
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: $0 <config-dir>" >&2
  exit 2
fi

config_dir="$1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# validate_role_list <field> <file>
# Validates that <field> is absent, or is a list of {entity_id, region, role}.
validate_role_list() {
  local field="$1" file="$2"

  local type
  type=$(yq eval ".${field} | type" "$file")

  if [ "$type" = "!!null" ]; then
    return 0
  fi

  if [ "$type" != "!!seq" ]; then
    echo "  ✗ ${field} must be a list" >&2
    return 1
  fi

  local count i entity_id region role ok=0
  count=$(yq eval ".${field} | length" "$file")

  for i in $(seq 0 $((count - 1))); do
    entity_id=$(yq eval ".${field}[$i].entity_id" "$file")
    region=$(yq eval ".${field}[$i].region" "$file")
    role=$(yq eval ".${field}[$i].role" "$file")

    if [ "$entity_id" = "null" ] || [ -z "$entity_id" ]; then
      echo "  ✗ ${field}[$i]: missing entity_id" >&2; ok=1
    fi
    if [ "$region" = "null" ] || [ -z "$region" ]; then
      echo "  ✗ ${field}[$i]: missing region" >&2; ok=1
    fi
    if [ "$role" = "null" ] || [ -z "$role" ]; then
      echo "  ✗ ${field}[$i]: missing role" >&2; ok=1
    fi
  done

  return $ok
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

yaml_files=$(find "$config_dir" -maxdepth 1 \( -name "*.yaml" -o -name "*.yml" \) | LC_ALL=C sort)

if [ -z "$yaml_files" ]; then
  echo "No YAML files found in $config_dir"
  exit 0
fi

echo "Validating team configs in $config_dir"
echo ""

# ---------------------------------------------------------------------------
# Per-file validation
# ---------------------------------------------------------------------------

errors=0

for file in $yaml_files; do
  echo "  $file"

  # 1. Valid YAML
  if ! yq eval '.' "$file" > /dev/null 2>&1; then
    echo "  ✗ invalid YAML syntax" >&2
    errors=$((errors + 1))
    continue
  fi

  # 2. name — required, lowercase alphanumeric + hyphens
  name=$(yq eval '.name' "$file")
  if [ "$name" = "null" ] || [ -z "$name" ]; then
    echo "  ✗ missing name" >&2
    errors=$((errors + 1))
    continue
  fi
  if echo "$name" | grep -qE '[^a-z0-9-]'; then
    echo "  ✗ invalid name '$name': must be lowercase alphanumeric with hyphens" >&2
    errors=$((errors + 1))
    continue
  fi

  # 3. offboarded — optional boolean
  offboarded=$(yq eval '.offboarded' "$file")
  if [ "$offboarded" != "null" ] && [ "$offboarded" != "true" ] && [ "$offboarded" != "false" ]; then
    echo "  ✗ offboarded must be true or false (got: $offboarded)" >&2
    errors=$((errors + 1))
    continue
  fi

  if [ "$offboarded" = "true" ]; then
    echo "  ✓ passed (offboarded)"
    continue
  fi

  # 4. entitlements — deprecated, warn if present
  entitlements_type=$(yq eval '.entitlements | type' "$file")
  if [ "$entitlements_type" = "!!seq" ]; then
    echo "  ⚠ 'entitlements' is deprecated — use control_plane_roles, api_roles, or api_product_roles" >&2
  elif [ "$entitlements_type" != "!!null" ]; then
    echo "  ✗ entitlements must be a list" >&2
    errors=$((errors + 1))
    continue
  fi

  # 5. Structured role lists
  file_ok=0
  validate_role_list "control_plane_roles" "$file" || file_ok=1
  validate_role_list "api_roles"           "$file" || file_ok=1
  validate_role_list "api_product_roles"   "$file" || file_ok=1

  if [ "$file_ok" -ne 0 ]; then
    errors=$((errors + 1))
  else
    echo "  ✓ passed"
  fi
done

echo ""
if [ "$errors" -ne 0 ]; then
  echo "$errors file(s) failed validation" >&2
  exit 1
fi

echo "All config files passed validation"
