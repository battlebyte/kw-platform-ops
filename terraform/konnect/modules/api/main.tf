terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_api" "this" {

  # Required fields
  name = var.name

  # Optional fields
  description  = var.description
  labels       = var.labels
  slug         = var.slug
  spec_content = var.spec_content
  version      = var.api_version
}
