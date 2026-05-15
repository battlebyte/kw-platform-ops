terraform {
  required_providers {
    konnect = {
      source = "kong/konnect"
    }
  }
}

locals {
  days_to_hours   = 365 * 24 // 1 year
  expiration_date = timeadd(formatdate("YYYY-MM-DD'T'HH:mm:ssZ", timestamp()), "${local.days_to_hours}h")
}

### Foreach team, create system accounts
resource "konnect_system_account" "this" {

  name        = "sa-${var.team_name}"
  description = "System account for creating control planes for the ${var.team_name} team"

  konnect_managed = false
}

# Assign the system accounts to the teams
resource "konnect_system_account_team" "this" {
  team_id = var.team_id

  account_id = konnect_system_account.this.id
}

### Add control plane roles — driven entirely by the control_plane_roles variable.
### Each entry specifies entity_id, region, and role, giving full flexibility
### (e.g. Admin on a specific CP in us, Creator on all CPs in eu, etc.)
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

### Add the api product creator role if team has the entitlement
resource "konnect_system_account_role" "ap_creators" {
  count = contains(var.team_entitlements, "konnect.api_product") ? 1 : 0

  entity_id        = "*"
  entity_region    = "eu" # Hardcoded for now
  entity_type_name = "API Products"
  role_name        = "Creator"
  account_id       = konnect_system_account.this.id
}

### Add the api product viewer role to every team system account
resource "konnect_system_account_role" "ap_viewers" {
  count = contains(var.team_entitlements, "konnect.api_product") ? 1 : 0

  entity_id        = "*"
  entity_region    = "eu" # Hardcoded for now
  entity_type_name = "API Products"
  role_name        = "Viewer"
  account_id       = konnect_system_account.this.id
}

### Add the api creator role if team has the entitlement
resource "konnect_system_account_role" "api_creators" {
  count = contains(var.team_entitlements, "konnect.api") ? 1 : 0

  entity_id        = "*"
  entity_region    = "eu" # Hardcoded for now
  entity_type_name = "APIs"
  role_name        = "Creator"
  account_id       = konnect_system_account.this.id
}

### Add the api viewer role if team has the entitlement
resource "konnect_system_account_role" "api_viewers" {
  count = contains(var.team_entitlements, "konnect.api") ? 1 : 0

  entity_id        = "*"
  entity_region    = "eu" # Hardcoded for now
  entity_type_name = "APIs"
  role_name        = "Viewer"
  account_id       = konnect_system_account.this.id
}

### Add the api publisher role if team has the entitlement
resource "konnect_system_account_role" "api_publishers" {
  count = contains(var.team_entitlements, "konnect.api") ? 1 : 0

  entity_id        = "*"
  entity_region    = "eu" # Hardcoded for now
  entity_type_name = "APIs"
  role_name        = "Publisher"
  account_id       = konnect_system_account.this.id
}

# Create an access token for every system account
resource "konnect_system_account_access_token" "this" {
  name       = "${konnect_system_account.this.name}-token"
  expires_at = local.expiration_date
  account_id = konnect_system_account.this.id

}

output "system_account_token" {
  value = konnect_system_account_access_token.this.token

  sensitive = true
}
