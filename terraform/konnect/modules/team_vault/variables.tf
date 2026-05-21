variable "team_name" {
  description = "Sanitised team name (lowercase, hyphens)"
  type        = string
}

variable "system_account_secret_path" {
  description = "KV path under the team mount where the system-account token is stored"
  type        = string
}

variable "system_account_token" {
  description = "The system account access token to store"
  type        = string
  sensitive   = true
}

variable "github_organization" {
  description = "GitHub organization name used for JWT role bound_claims"
  type        = string
  default     = "KongHQ-CX"
}
