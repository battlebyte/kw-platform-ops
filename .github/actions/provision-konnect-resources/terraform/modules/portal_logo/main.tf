terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_portal_logo" "this" {
  portal_id = var.portal_id
  data      = var.data
}
