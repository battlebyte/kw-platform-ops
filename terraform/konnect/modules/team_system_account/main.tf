terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_system_account" "this" {
  name            = "sa-${var.team_name}"
  description     = "System account for the ${var.team_name} team"
  konnect_managed = false
}

resource "konnect_system_account_team" "this" {
  team_id    = var.team_id
  account_id = konnect_system_account.this.id
}

resource "konnect_system_account_role" "cp_roles" {
  for_each = {
    for r in var.control_plane_roles :
    "${r.role}-${r.entity_id}-${r.region}" => r
  }

  entity_id        = each.value.entity_id
  entity_region    = each.value.region
  entity_type_name = "Control Planes"
  role_name        = each.value.role
  account_id       = konnect_system_account.this.id
}

resource "konnect_system_account_role" "api_roles" {
  for_each = {
    for r in var.api_roles :
    "${r.role}-${r.entity_id}-${r.region}" => r
  }

  entity_id        = each.value.entity_id
  entity_region    = each.value.region
  entity_type_name = "APIs"
  role_name        = each.value.role
  account_id       = konnect_system_account.this.id
}

resource "konnect_system_account_role" "api_product_roles" {
  for_each = {
    for r in var.api_product_roles :
    "${r.role}-${r.entity_id}-${r.region}" => r
  }

  entity_id        = each.value.entity_id
  entity_region    = each.value.region
  entity_type_name = "API Products"
  role_name        = each.value.role
  account_id       = konnect_system_account.this.id
}

resource "konnect_system_account_access_token" "this" {
  name       = "${konnect_system_account.this.name}-token"
  expires_at = var.expires_at
  account_id = konnect_system_account.this.id

  # expires_at is ForceNew. Ignore drift so expiry changes don't silently rotate
  # tokens — rotation should be an explicit action (destroy + re-apply).
  lifecycle {
    ignore_changes = [expires_at]
  }
}

output "system_account_token" {
  value     = konnect_system_account_access_token.this.token
  sensitive = true
}
