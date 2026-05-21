resource "konnect_gateway_plugin_prometheus" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.prometheus.enabled, false) }

  config           = try(each.value.plugins.prometheus.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_opentelemetry" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.opentelemetry.enabled, false) }

  config = merge(
    try(each.value.plugins.opentelemetry.config, {}),
    try(each.value.plugins.opentelemetry.config.headers, null) != null ? {
      headers = { for k, v in each.value.plugins.opentelemetry.config.headers : k => jsonencode(v) }
    } : {},
    try(each.value.plugins.opentelemetry.config.resource_attributes, null) != null ? {
      resource_attributes = { for k, v in each.value.plugins.opentelemetry.config.resource_attributes : k => jsonencode(v) }
    } : {}
  )
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_rate_limiting_advanced" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.rate_limiting_advanced.enabled, false) }

  config           = try(each.value.plugins.rate_limiting_advanced.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_file_log" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.file_log.enabled, false) }

  config           = try(each.value.plugins.file_log.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_cors" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.cors.enabled, false) }

  config           = try(each.value.plugins.cors.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_openid_connect" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.openid_connect.enabled, false) }

  config           = try(each.value.plugins.openid_connect.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_request_termination" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.request_termination.enabled, false) }

  config           = try(each.value.plugins.request_termination.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_pre_function" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.pre_function.enabled, false) }

  config           = try(each.value.plugins.pre_function.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}

resource "konnect_gateway_plugin_post_function" "service" {
  for_each = { for name, service in local.services_map : name => service if try(service.plugins.post_function.enabled, false) }

  config           = try(each.value.plugins.post_function.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  service          = { id = konnect_gateway_service.this[each.key].id }
}
