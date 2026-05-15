terraform {
  required_providers {
    konnect-beta = {
      source  = "Kong/konnect-beta"
      version = "0.17.0"
    }
  }
}

resource "konnect_dashboard" "this" {
  provider = konnect-beta
  name = var.name

  labels     = var.labels
  definition = var.definition
}
