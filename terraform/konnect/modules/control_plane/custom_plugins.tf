resource "konnect_gateway_custom_plugin_schema" "this" {
  for_each = local.is_control_plane ? {
    for plugin in try(var.custom_plugins, []) : plugin.name => plugin
    if can(plugin.lua_schema_file)
  } : {}

  control_plane_id = konnect_gateway_control_plane.this.id
  lua_schema       = file("${path.root}/${each.value.lua_schema_file}")
}

resource "konnect_gateway_custom_plugin" "this" {
  for_each = local.is_control_plane ? {
    for plugin in try(var.custom_plugins, []) : plugin.name => plugin
    if can(plugin.config)
  } : {}

  name             = each.value.name
  instance_name    = try(each.value.instance_name, "global-${each.value.name}")
  config           = try(each.value.config, {})
  control_plane_id = konnect_gateway_control_plane.this.id
  enabled          = try(each.value.enabled, true)
  tags             = local.tags

  depends_on = [konnect_gateway_custom_plugin_schema.this]
}
