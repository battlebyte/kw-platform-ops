resource "konnect_gateway_plugin_prometheus" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.prometheus.enabled, false) }

  config           = try(each.value.route.plugins.prometheus.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_opentelemetry" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.opentelemetry.enabled, false) }

  config = merge(
    try(each.value.route.plugins.opentelemetry.config, {}),
    try(each.value.route.plugins.opentelemetry.config.headers, null) != null ? {
      headers = { for k, v in each.value.route.plugins.opentelemetry.config.headers : k => jsonencode(v) }
    } : {},
    try(each.value.route.plugins.opentelemetry.config.resource_attributes, null) != null ? {
      resource_attributes = { for k, v in each.value.route.plugins.opentelemetry.config.resource_attributes : k => jsonencode(v) }
    } : {}
  )
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_rate_limiting_advanced" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.rate_limiting_advanced.enabled, false) }

  config           = try(each.value.route.plugins.rate_limiting_advanced.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_file_log" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.file_log.enabled, false) }

  config           = try(each.value.route.plugins.file_log.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_cors" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.cors.enabled, false) }

  config           = try(each.value.route.plugins.cors.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_openid_connect" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.openid_connect.enabled, false) }

  config           = try(each.value.route.plugins.openid_connect.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_request_termination" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.request_termination.enabled, false) }

  config           = try(each.value.route.plugins.request_termination.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_pre_function" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.pre_function.enabled, false) }

  config           = try(each.value.route.plugins.pre_function.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}

resource "konnect_gateway_plugin_post_function" "route" {
  for_each = { for key, item in local.routes_map : key => item if try(item.route.plugins.post_function.enabled, false) }

  config           = try(each.value.route.plugins.post_function.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = true
  tags             = local.tags
  route            = { id = konnect_gateway_route.this[each.key].id }
}
