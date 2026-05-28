terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_mesh_control_plane" "this" {
  name        = var.name
  description = var.description
  labels      = length(var.labels) > 0 ? var.labels : null
  features    = length(var.features) > 0 ? var.features : null
}

output "id" {
  description = "The Mesh Control Plane ID"
  value       = konnect_mesh_control_plane.this.id
}

output "name" {
  description = "The Mesh Control Plane name"
  value       = konnect_mesh_control_plane.this.name
}
