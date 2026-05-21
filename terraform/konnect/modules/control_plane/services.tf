locals {
  services_map = local.is_control_plane ? {
    for service in try(var.services, []) : service.name => service
  } : {}

  service_routes = flatten([
    for service in try(var.services, []) : [
      for route in try(service.routes, []) : {
        key          = "service:${service.name}:${route.name}"
        service_name = service.name
        route        = route
      }
    ]
  ])

  standalone_routes = [
    for route in try(var.routes, []) : {
      key          = "route:${route.name}"
      service_name = null
      route        = route
    }
  ]

  routes_map = local.is_control_plane ? {
    for item in concat(local.service_routes, local.standalone_routes) : item.key => item
  } : {}
}

resource "konnect_gateway_service" "this" {
  for_each = local.services_map

  name             = each.value.name
  host             = each.value.host
  port             = try(each.value.port, 80)
  protocol         = try(each.value.protocol, "http")
  path             = try(each.value.path, null)
  retries          = try(each.value.retries, 5)
  connect_timeout  = try(each.value.connect_timeout, 60000)
  read_timeout     = try(each.value.read_timeout, 60000)
  write_timeout    = try(each.value.write_timeout, 60000)
  enabled          = try(each.value.enabled, true)
  tags             = try(each.value.tags, [])
  control_plane_id = konnect_gateway_control_plane.this.id
}

resource "konnect_gateway_route" "this" {
  for_each = local.routes_map

  name                       = each.value.route.name
  protocols                  = try(each.value.route.protocols, ["http", "https"])
  hosts                      = try(each.value.route.hosts, null)
  paths                      = try(each.value.route.paths, null)
  methods                    = try(each.value.route.methods, null)
  headers                    = try(each.value.route.headers, null)
  strip_path                 = try(each.value.route.strip_path, true)
  preserve_host              = try(each.value.route.preserve_host, false)
  regex_priority             = try(each.value.route.regex_priority, 0)
  https_redirect_status_code = try(each.value.route.https_redirect_status_code, 426)
  request_buffering          = try(each.value.route.request_buffering, true)
  response_buffering         = try(each.value.route.response_buffering, true)
  tags                       = try(each.value.route.tags, [])
  control_plane_id           = konnect_gateway_control_plane.this.id

  service = each.value.service_name != null ? {
    id = konnect_gateway_service.this[each.value.service_name].id
  } : null
}
