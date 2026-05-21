resource "konnect_gateway_upstream" "this" {
  for_each = local.is_control_plane ? {
    for upstream in try(var.upstreams, []) : upstream.name => upstream
  } : {}

  name                = each.value.name
  control_plane_id    = konnect_gateway_control_plane.this.id
  algorithm           = try(each.value.algorithm, "round-robin")
  host_header         = try(each.value.host_header, null)
  slots               = try(each.value.slots, 10000)
  use_srv_name        = try(each.value.use_srv_name, false)
  hash_on             = try(each.value.hash_on, "none")
  hash_fallback       = try(each.value.hash_fallback, "none")
  hash_on_cookie_path = try(each.value.hash_on_cookie_path, "/")
  healthchecks        = try(each.value.healthchecks, null)
  tags                = try(each.value.tags, [])
}

resource "konnect_gateway_target" "this" {
  for_each = local.is_control_plane ? {
    for item in flatten([
      for upstream in try(var.upstreams, []) : [
        for target in try(upstream.targets, []) : {
          key           = "${upstream.name}:${try(target.name, target.target)}"
          upstream_name = upstream.name
          target        = target.target
          weight        = try(target.weight, 100)
          tags          = try(target.tags, [])
          failover      = try(target.failover, false)
        }
      ]
    ]) : item.key => item
  } : {}

  target           = each.value.target
  weight           = each.value.weight
  tags             = each.value.tags
  failover         = each.value.failover
  upstream_id      = konnect_gateway_upstream.this[each.value.upstream_name].id
  control_plane_id = konnect_gateway_control_plane.this.id
}
