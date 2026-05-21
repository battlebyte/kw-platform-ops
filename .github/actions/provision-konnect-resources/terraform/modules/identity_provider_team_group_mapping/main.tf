terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_identity_provider_team_group_mapping" "this" {
  group                = var.group
  identity_provider_id = var.identity_provider_id
  team_id              = var.team_id
}
