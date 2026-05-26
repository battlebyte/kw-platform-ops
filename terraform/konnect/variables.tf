variable "org" {
  description = "Konnect organisation name. Selects konnect/orgs/<org> by default."
  type        = string
  default     = "konnect"
}

variable "config_dir" {
  description = "Exact directory containing the org YAML files. Defaults to ../../konnect/orgs/<org>."
  type        = string
  default     = null
}

variable "config_file_path" {
  description = "Parent directory containing org subdirectories. Used as <config_file_path>/<org> when config_dir is unset."
  type        = string
  default     = null
}

variable "konnect_server_url" {
  description = "The URL of the Konnect server to connect to."
  type        = string
  default     = "https://eu.api.konghq.com"
}

variable "konnect_access_token" {
  description = "The Konnect access token to use for API requests."
  type        = string
  default     = null
  sensitive   = true
}

variable "konnect_token" {
  description = "Backward-compatible alias for konnect_access_token."
  type        = string
  default     = null
  sensitive   = true
}

variable "konnect_region" {
  description = "The Konnect region to use for region-scoped role assignments."
  type        = string
  default     = "eu"
}

variable "vault_address" {
  description = "HashiCorp Vault address for system-account token storage."
  type        = string
  default     = "http://localhost:8300"
}

variable "vault_token" {
  description = "HashiCorp Vault token."
  type        = string
  default     = null
  sensitive   = true
}

variable "github_organization" {
  description = "GitHub organization name used for Vault JWT role bound_claims."
  type        = string
  default     = "KongHQ-CX"
}

variable "gh_workspace_path" {
  description = "GitHub workspace path used when YAML references file-backed API content."
  type        = string
  default     = "../.."
}

variable "sensitive_vars" {
  description = "Sensitive values for gateway vault config substitution. Keys are referenced as __key__ in YAML."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "create_team_vault_secrets" {
  description = "Whether to create team Vault mounts and store generated team system-account tokens."
  type        = bool
  default     = true
}

variable "create_system_account_vault_secrets" {
  description = "Whether to create a shared Vault mount for explicit system-account access tokens."
  type        = bool
  default     = true
}

variable "system_account_vault_mount" {
  description = "Shared KV v2 mount used for explicit system-account access tokens."
  type        = string
  default     = "system-accounts-kv"
}

variable "default_system_account_token_expires_at" {
  # NOTE: Konnect API requires this date to be within one year of `terraform apply`. Update annually.
  description = "Stable default expiry timestamp for generated system-account access tokens. Must be within one year of the apply date per the Konnect API."
  type        = string
  default     = "2027-05-25T00:00:00Z"
}
