terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.4.0"
    }
  }
}

data "vault_auth_backend" "this" {
  path = "github-actions"
}

resource "vault_mount" "this" {
  path        = "${var.team_name}-kv"
  type        = "kv"
  options     = { version = "2" }
  description = "Vault mount for the ${var.team_name} team"
}

resource "vault_policy" "this" {
  name = "${vault_mount.this.path}-policy"

  policy = <<EOT
path "${vault_mount.this.path}/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "${vault_mount.this.path}/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "${vault_mount.this.path}/delete/*" {
  capabilities = ["update"]
}

path "${vault_mount.this.path}/undelete/*" {
  capabilities = ["update"]
}

path "${vault_mount.this.path}/destroy/*" {
  capabilities = ["update"]
}

path "${vault_mount.this.path}/metadata" {
  capabilities = ["list"]
}

path "auth/token/create" {
  capabilities = ["create", "update"]
}

path "auth/token/renew" {
  capabilities = ["update"]
}

path "auth/token/revoke" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

resource "vault_jwt_auth_backend_role" "github_repo" {
  backend        = data.vault_auth_backend.this.path
  role_name      = "${var.team_name}-gh-repo-role"
  token_policies = [vault_policy.this.name]

  bound_audiences = ["https://github.com/${var.github_organization}"]

  bound_claims = {
    repository = "${var.github_organization}/kw-${var.team_name}-repo"
  }

  user_claim     = "sub"
  role_type      = "jwt"
  token_ttl      = 1800
  token_max_ttl  = 3600
  token_num_uses = 0
}

resource "vault_kv_secret_v2" "this" {
  mount               = vault_mount.this.path
  name                = var.system_account_secret_path
  delete_all_versions = true
  data_json = jsonencode({
    token = var.system_account_token
  })
  custom_metadata {
    max_versions = 5
  }
}
