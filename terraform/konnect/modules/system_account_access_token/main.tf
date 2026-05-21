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
