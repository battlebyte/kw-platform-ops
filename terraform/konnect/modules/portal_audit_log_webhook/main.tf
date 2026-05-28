terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_portal_audit_log_webhook" "this" {
  portal_id                = var.portal_id
  audit_log_destination_id = var.audit_log_destination_id
  enabled                  = var.enabled
}

output "portal_id" {
  description = "The Portal ID this webhook is attached to"
  value       = konnect_portal_audit_log_webhook.this.portal_id
}
