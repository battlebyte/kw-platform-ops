locals {
  processed_vaults = local.is_control_plane ? [
    for vault in try(var.vaults, []) : {
      name        = vault.name
      prefix      = try(vault.prefix, null)
      description = try(vault.description, null)
      tags        = try(vault.tags, [])
      config = jsonencode({
        for key, value in try(vault.config, {}) :
        key => (
          can(regex("^__(.+)__$", tostring(value))) ?
          var.sensitive_vars[regex("^__(.+)__$", tostring(value))[0]] :
          value
        )
      })
    }
  ] : []

  unresolved_vault_placeholders = [
    for vault in local.processed_vaults : vault.name
    if can(regex("__[A-Za-z0-9_]+__", vault.config))
  ]
}

resource "konnect_gateway_vault" "this" {
  for_each = {
    for vault in local.processed_vaults : vault.name => vault
  }

  name             = each.value.name
  prefix           = each.value.prefix
  description      = each.value.description
  config           = each.value.config
  control_plane_id = konnect_gateway_control_plane.this.id
  tags             = each.value.tags
}
