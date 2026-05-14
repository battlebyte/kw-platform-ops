#!/bin/sh
set -e

# Non-interactive vault PKI setup — called by the Makefile's vault-pki target
# inside the vault docker container.
# Usage: vault-pki-setup.sh <VAULT_ADDR> <VAULT_TOKEN> <GITHUB_ORG>

VAULT_ADDR="${1:-http://0.0.0.0:8300}"
VAULT_TOKEN="${2:-root}"
GITHUB_ORG="${3:-}"

PKI_MOUNT_PATH="pki"
CERT_TTL="43800h"
COMMON_NAME_ROOT="ca.kong.edu.local"
ROLE_NAME="kong"
ROLE_ALLOWED_DOMAINS="kong.edu.local"
CERT_TTL_ROLE="4380h"

export VAULT_ADDR
export VAULT_TOKEN

# Wait for Vault to be ready before issuing commands
_vault_retries=0
until vault status > /dev/null 2>&1; do
    _vault_retries=$((_vault_retries + 1))
    if [ "${_vault_retries}" -ge 30 ]; then
        echo "ERROR: Vault not ready after 30 seconds. Check that the Vault container is running."
        exit 1
    fi
    sleep 1
done

echo "Vault PKI setup starting (addr=${VAULT_ADDR}, github_org=${GITHUB_ORG})..."

# Enable PKI secrets engine if not already enabled
VAULT_SECRETS=$(vault secrets list -format=table)
if ! echo "${VAULT_SECRETS}" | grep -q "^${PKI_MOUNT_PATH}/"; then
    vault secrets enable -path="${PKI_MOUNT_PATH}" -max-lease-ttl="${CERT_TTL}" pki
    echo "PKI secrets engine enabled at ${PKI_MOUNT_PATH}."
else
    echo "PKI secrets engine already enabled at ${PKI_MOUNT_PATH} — skipping."
fi

# Generate root CA if not already present
if ! vault read -field=certificate "${PKI_MOUNT_PATH}/cert/ca" > /dev/null 2>&1; then
    vault write "${PKI_MOUNT_PATH}/root/generate/internal" \
        common_name="${COMMON_NAME_ROOT}" \
        ttl="${CERT_TTL}"
    echo "Root CA generated for ${COMMON_NAME_ROOT}."
else
    echo "Root CA already exists — skipping."
fi

# Configure URLs
vault write "${PKI_MOUNT_PATH}/config/urls" \
    issuing_certificates="${VAULT_ADDR}/v1/${PKI_MOUNT_PATH}/ca" \
    crl_distribution_points="${VAULT_ADDR}/v1/${PKI_MOUNT_PATH}/crl"
echo "CA endpoint URLs configured."

# Create role if not already present
if ! vault read "${PKI_MOUNT_PATH}/roles/${ROLE_NAME}" > /dev/null 2>&1; then
    vault write "${PKI_MOUNT_PATH}/roles/${ROLE_NAME}" \
        allowed_domains="${ROLE_ALLOWED_DOMAINS}" \
        allow_subdomains=true \
        max_ttl="${CERT_TTL_ROLE}"
    echo "Role '${ROLE_NAME}' created."
else
    echo "Role '${ROLE_NAME}' already exists — skipping."
fi

# Configure GitHub auth if org is provided
if [ -n "${GITHUB_ORG}" ] && [ "${GITHUB_ORG}" != "null" ]; then
    VAULT_AUTH=$(vault auth list -format=table)
    if ! echo "${VAULT_AUTH}" | grep -q "^github/"; then
        vault auth enable github
        echo "GitHub auth method enabled."
    else
        echo "GitHub auth method already enabled."
    fi
    vault write auth/github/config organization="${GITHUB_ORG}"
    echo "GitHub organization configured: ${GITHUB_ORG}."
fi

# Enable AppRole auth method if not already enabled
VAULT_AUTH=$(vault auth list -format=table)
if ! echo "${VAULT_AUTH}" | grep -q "^approle/"; then
    vault auth enable approle
    echo "AppRole auth method enabled."
else
    echo "AppRole auth method already enabled."
fi

# Enable and configure JWT/OIDC auth backend for GitHub Actions
JWT_PATH="github-actions"
OIDC_DISCOVERY_URL="https://token.actions.githubusercontent.com"
VAULT_AUTH=$(vault auth list -format=table)
if ! echo "${VAULT_AUTH}" | grep -q "^${JWT_PATH}/"; then
    vault auth enable -path="${JWT_PATH}" jwt
    echo "JWT/OIDC auth backend enabled at path '${JWT_PATH}'."
else
    echo "JWT/OIDC auth backend already enabled at path '${JWT_PATH}'."
fi

if [ -n "${GITHUB_ORG}" ] && [ "${GITHUB_ORG}" != "null" ]; then
    BOUND_AUDIENCE="https://github.com/${GITHUB_ORG}"
    vault write "auth/${JWT_PATH}/config" \
        oidc_discovery_url="${OIDC_DISCOVERY_URL}" \
        bound_issuer="${OIDC_DISCOVERY_URL}" \
        default_role="github-actions"
    vault write "auth/${JWT_PATH}/role/github-actions" \
        role_type="jwt" \
        user_claim="sub" \
        bound_audiences="${BOUND_AUDIENCE}" \
        token_policies="default" \
        token_ttl="1h" \
        token_max_ttl="4h"
    echo "JWT/OIDC auth backend for GitHub Actions configured."
fi

echo "Vault PKI setup complete."
