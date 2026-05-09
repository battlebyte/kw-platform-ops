terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.15.0"
    }
  }
}

resource "konnect_team_user" "this" {
  team_id = var.team_id
  user_id = var.user_id
}
