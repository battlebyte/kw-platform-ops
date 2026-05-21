resource "konnect_gateway_plugin_prometheus" "this" {
  for_each = local.is_control_plane && try(var.plugins.prometheus.enabled, false) ? { this = var.plugins.prometheus } : {}

  config           = try(each.value.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
}

resource "konnect_gateway_plugin_opentelemetry" "this" {
  for_each = local.is_control_plane && try(var.plugins.opentelemetry.enabled, false) ? { this = var.plugins.opentelemetry } : {}

  config = merge(
    try(each.value.config, {}),
    try(each.value.config.headers, null) != null ? {
      headers = { for k, v in each.value.config.headers : k => jsonencode(v) }
    } : {},
    try(each.value.config.resource_attributes, null) != null ? {
      resource_attributes = { for k, v in each.value.config.resource_attributes : k => jsonencode(v) }
    } : {}
  )
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
}

resource "konnect_gateway_plugin_rate_limiting_advanced" "this" {
  for_each = local.is_control_plane && try(var.plugins.rate_limiting_advanced.enabled, false) ? { this = var.plugins.rate_limiting_advanced } : {}

  config           = try(each.value.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
}

resource "konnect_gateway_plugin_file_log" "this" {
  for_each = local.is_control_plane && try(var.plugins.file_log.enabled, false) ? { this = var.plugins.file_log } : {}

  config           = try(each.value.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
}

resource "konnect_gateway_plugin_cors" "this" {
  for_each = local.is_control_plane && try(var.plugins.cors.enabled, false) ? { this = var.plugins.cors } : {}

  config           = try(each.value.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
}

resource "konnect_gateway_plugin_openid_connect" "this" {
  for_each = local.is_control_plane && try(var.plugins.openid_connect.enabled, false) ? { this = var.plugins.openid_connect } : {}

  config           = try(each.value.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
}
