terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_portal_custom_domain" "this" {
  portal_id = var.portal_id
  hostname  = var.hostname
  enabled   = var.enabled
  ssl = {
    type                       = var.ssl_type
    domain_verification_method = var.ssl_domain_verification_method
  }
}

output "hostname" {
  value       = konnect_portal_custom_domain.this.hostname
  description = "Custom domain hostname"
}
