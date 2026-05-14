#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRET_FILE="${REPO_ROOT}/act.secrets"
EXAMPLE_FILE="${REPO_ROOT}/act.secrets.example"

if [[ -f "$SECRET_FILE" ]]; then
    echo "act.secrets already exists — skipping. Edit it directly to update secrets."
    exit 0
fi

if [[ ! -f "$EXAMPLE_FILE" ]]; then
    echo "ERROR: act.secrets.example not found at ${EXAMPLE_FILE}."
    echo "Ensure the repository is fully checked out and act.secrets.example exists at the repo root."
    exit 1
fi

if [[ ! -r "$EXAMPLE_FILE" ]]; then
    echo "ERROR: act.secrets.example exists but is not readable (check file permissions)."
    exit 1
fi

trap 'rm -f "$SECRET_FILE"' ERR
cp "$EXAMPLE_FILE" "$SECRET_FILE"
chmod 600 "$SECRET_FILE"
trap - ERR

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
