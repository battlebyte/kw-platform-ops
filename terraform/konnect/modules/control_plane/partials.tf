resource "konnect_gateway_partial" "this" {
  for_each = local.is_control_plane ? {
    for partial in try(var.partials, []) : partial.name => partial
  } : {}

  redis_ce         = can(each.value.redis_ce) ? merge({ tags = local.tags }, each.value.redis_ce) : null
  redis_ee         = can(each.value.redis_ee) ? merge({ tags = local.tags }, each.value.redis_ee) : null
  control_plane_id = konnect_gateway_control_plane.this.id
}
