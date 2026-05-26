terraform {
  required_providers {
    konnect = {
      source = "kong/konnect"
    }
  }
}

locals {
  is_control_plane              = var.cluster_type != "CLUSTER_TYPE_CONTROL_PLANE_GROUP"
  default_auth_type             = "pki_client_certs"
  tags                          = ["global_entities", "governance", "platform"]
  supported_global_plugin_names = toset(["prometheus", "opentelemetry", "rate_limiting_advanced", "file_log", "cors", "openid_connect"])
  supported_scoped_plugin_names = setunion(local.supported_global_plugin_names, toset(["request_termination", "pre_function", "post_function"]))
  unsupported_global_plugins = [
    for name, plugin in try(var.plugins, {}) : name
    if try(plugin.enabled, false) && !contains(local.supported_global_plugin_names, name)
  ]
  unsupported_service_plugins = flatten([
    for service in try(var.services, []) : [
      for name, plugin in try(service.plugins, {}) : "${service.name}.${name}"
      if try(plugin.enabled, false) && !contains(local.supported_scoped_plugin_names, name)
    ]
  ])
  unsupported_route_plugins = flatten([
    for item in local.routes_map : [
      for name, plugin in try(item.route.plugins, {}) : "${item.key}.${name}"
      if try(plugin.enabled, false) && !contains(local.supported_scoped_plugin_names, name)
    ]
  ])
  unsupported_plugins = concat(local.unsupported_global_plugins, local.unsupported_service_plugins, local.unsupported_route_plugins)
  invalid_partials = [
    for partial in try(var.partials, []) : partial.name
    if !can(partial.redis_ee) && !can(partial.redis_ce)
  ]
}

resource "terraform_data" "validate_control_plane_config" {
  input = var.name

  lifecycle {
    precondition {
      condition     = length(local.unsupported_plugins) == 0
      error_message = "Unsupported enabled gateway plugin declarations for ${var.name}: ${join(", ", local.unsupported_plugins)}."
    }

    precondition {
      condition     = length(local.invalid_partials) == 0
      error_message = "Partials for ${var.name} must declare redis_ee or redis_ce: ${join(", ", local.invalid_partials)}."
    }

    precondition {
      condition     = length(local.unresolved_vault_placeholders) == 0
      error_message = "Vault configs for ${var.name} contain unresolved __secret__ placeholders: ${join(", ", local.unresolved_vault_placeholders)}."
    }
  }
}

resource "konnect_gateway_control_plane" "this" {
  name          = var.name
  description   = var.description
  cluster_type  = var.cluster_type
  auth_type     = var.auth_type != null ? var.auth_type : local.default_auth_type
  cloud_gateway = local.is_control_plane ? var.cloud_gateway : false
  proxy_urls    = local.is_control_plane ? var.proxy_urls : []
  labels = merge(var.labels, {
    generated_by = "terraform"
  })

  # cluster_type and cloud_gateway are ForceNew immutable attributes. Ignore them
  # after initial creation to prevent accidental destroy-recreate on import drift.
  lifecycle {
    ignore_changes = [cluster_type, cloud_gateway]
  }
}

output "control_plane" {
  description = "Control plane details."
  value = {
    id           = konnect_gateway_control_plane.this.id
    name         = konnect_gateway_control_plane.this.name
    description  = konnect_gateway_control_plane.this.description
    cluster_type = konnect_gateway_control_plane.this.cluster_type
    auth_type    = konnect_gateway_control_plane.this.auth_type
    labels       = konnect_gateway_control_plane.this.labels
    config       = konnect_gateway_control_plane.this.config
  }
}
