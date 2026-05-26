terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_system_account_access_token" "this" {
  account_id = var.account_id
  name       = var.name
  expires_at = var.expires_at

  # expires_at is a ForceNew attribute. Ignore drift so that expiry changes
  # don't silently rotate tokens — token rotation should be an explicit action.
  lifecycle {
    ignore_changes = [expires_at]
  }
}

output "id" {
  value       = konnect_system_account_access_token.this.id
  description = "System account access token ID"
}

output "token" {
  value       = konnect_system_account_access_token.this.token
  description = "The generated token"
  sensitive   = true
}
