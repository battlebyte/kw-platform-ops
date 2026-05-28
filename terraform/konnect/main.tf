locals {
  config_path          = var.config_dir != null ? var.config_dir : var.config_file_path != null ? "${var.config_file_path}/${var.org}" : "${path.root}/../../konnect/orgs/${var.org}"
  config_files         = sort(fileset(local.config_path, "*.yaml"))
  config_documents     = [for file in local.config_files : yamldecode(file("${local.config_path}/${file}"))]
  config_keys          = distinct(flatten([for document in local.config_documents : keys(document)]))
  config_values_by_key = { for key in local.config_keys : key => [for document in local.config_documents : document[key] if contains(keys(document), key)] }
  org_config = {
    for key, values in local.config_values_by_key : key => (
      alltrue([for value in values : can(tolist(value))]) ? flatten([for value in values : tolist(value)]) :
      alltrue([for value in values : can(tomap(value))]) ? merge([for value in values : tomap(value)]...) :
      values[length(values) - 1]
    )
  }
  labels        = lookup(local.org_config, "labels", {})
  konnect_token = coalesce(var.konnect_access_token, var.konnect_token, "")
  uuid_pattern  = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  control_plane_groups = [
    for group in lookup(local.org_config, "control_plane_groups", []) : merge(group, {
      cluster_type = "CLUSTER_TYPE_CONTROL_PLANE_GROUP"
      labels       = merge(local.labels, lookup(group, "labels", {}))
    })
  ]

  control_planes = [
    for cp in lookup(local.org_config, "control_planes", []) : merge(cp, {
      cluster_type = lookup(cp, "cluster_type", "CLUSTER_TYPE_CONTROL_PLANE")
      labels       = merge(local.labels, lookup(cp, "labels", {}))
    })
  ]

  all_control_planes = {
    for cp in concat(local.control_plane_groups, local.control_planes) : cp.name => cp
  }

  control_plane_memberships = flatten([
    for cp_name, cp in local.all_control_planes : [
      for group_name in lookup(cp, "group_memberships", []) : {
        key        = "${cp_name}:${group_name}"
        cp_name    = cp_name
        group_name = group_name
      }
    ]
  ])

  teams = lookup(local.org_config, "teams", [])
  teams_by_name = {
    for team in local.teams : team.name => team
  }
  sanitized_team_names = {
    for team in local.teams : team.name => trim(replace(replace(lower(team.name), "/[^a-z0-9-]/", "-"), "/-+/", "-"), "-")
  }
  sanitized_team_name_values = values(local.sanitized_team_names)

  sanofi_team_role_bindings = flatten([
    for team in local.teams : [
      for role in lookup(team, "roles", []) : [
        for entity_name in lookup(role, "entity_names", ["*"]) : {
          team_name        = team.name
          role_name        = lookup(role, "name", lookup(role, "role", null))
          entity_type_name = lookup(role, "entity_type_name", null)
          entity_region    = lookup(role, "entity_region", var.konnect_region)
          entity_name      = entity_name
        }
      ]
    ]
  ])

  legacy_team_control_plane_role_bindings = flatten([
    for team in local.teams : [
      for role in lookup(team, "control_plane_roles", []) : {
        team_name        = team.name
        role_name        = role.role
        entity_type_name = "Control Planes"
        entity_region    = lookup(role, "region", var.konnect_region)
        entity_name      = lookup(role, "entity_id", "*")
      }
    ]
  ])

  legacy_team_api_role_bindings = flatten([
    for team in local.teams : [
      for role in lookup(team, "api_roles", []) : {
        team_name        = team.name
        role_name        = role.role
        entity_type_name = "APIs"
        entity_region    = lookup(role, "region", var.konnect_region)
        entity_name      = lookup(role, "entity_id", "*")
      }
    ]
  ])

  legacy_team_api_product_role_bindings = flatten([
    for team in local.teams : [
      for role in lookup(team, "api_product_roles", []) : {
        team_name        = team.name
        role_name        = role.role
        entity_type_name = "API Products"
        entity_region    = lookup(role, "region", var.konnect_region)
        entity_name      = lookup(role, "entity_id", "*")
      }
    ]
  ])

  team_role_bindings = concat(
    local.sanofi_team_role_bindings,
    local.legacy_team_control_plane_role_bindings,
    local.legacy_team_api_role_bindings,
    local.legacy_team_api_product_role_bindings
  )

  system_accounts = lookup(local.org_config, "system_accounts", [])
  sanitized_system_account_names = {
    for account in local.system_accounts : account.name => trim(replace(replace(lower(account.name), "/[^a-z0-9-]/", "-"), "/-+/", "-"), "-")
  }

  system_account_role_bindings = flatten([
    for account in local.system_accounts : [
      for role in lookup(account, "roles", []) : [
        for entity_name in lookup(role, "entity_names", ["*"]) : {
          account_name     = account.name
          role_name        = lookup(role, "name", lookup(role, "role", null))
          entity_type_name = lookup(role, "entity_type_name", null)
          entity_region    = lookup(role, "entity_region", var.konnect_region)
          entity_name      = entity_name
        }
      ]
    ]
  ])

  team_system_account_control_plane_roles = {
    for team in local.teams : team.name => [
      for role in concat(local.sanofi_team_role_bindings, local.legacy_team_control_plane_role_bindings) : {
        role      = role.role_name
        region    = role.entity_region
        entity_id = role.entity_name == "*" ? "*" : can(regex(local.uuid_pattern, role.entity_name)) ? role.entity_name : local.entity_ids_by_type_and_name["Control Planes"][role.entity_name]
      }
      if role.team_name == team.name && role.entity_type_name == "Control Planes"
    ]
  }

  team_system_account_api_roles = {
    for team in local.teams : team.name => [
      for role in concat(local.sanofi_team_role_bindings, local.legacy_team_api_role_bindings) : {
        role      = role.role_name
        region    = role.entity_region
        entity_id = role.entity_name == "*" ? "*" : can(regex(local.uuid_pattern, role.entity_name)) ? role.entity_name : local.entity_ids_by_type_and_name["APIs"][role.entity_name]
      }
      if role.team_name == team.name && role.entity_type_name == "APIs"
    ]
  }

  team_system_account_api_product_roles = {
    for team in local.teams : team.name => [
      for role in concat(local.sanofi_team_role_bindings, local.legacy_team_api_product_role_bindings) : {
        role      = role.role_name
        region    = role.entity_region
        entity_id = role.entity_name == "*" ? "*" : can(regex(local.uuid_pattern, role.entity_name)) ? role.entity_name : local.entity_ids_by_type_and_name["API Products"][role.entity_name]
      }
      if role.team_name == team.name && role.entity_type_name == "API Products"
    ]
  }

  apis              = lookup(local.org_config, "apis", lookup(local.org_config, "api_products", []))
  api_versions      = lookup(local.org_config, "api_versions", [])
  api_documents     = lookup(local.org_config, "api_documents", [])
  api_publications  = lookup(local.org_config, "api_publications", [])
  auth_strategies   = lookup(local.org_config, "application_auth_strategies", [])
  portals           = lookup(local.org_config, "portals", [])
  portal_auths      = lookup(local.org_config, "portal_auths", [])
  portal_teams      = lookup(local.org_config, "portal_teams", [])
  portal_domains    = lookup(local.org_config, "portal_custom_domains", [])
  customizations    = lookup(local.org_config, "portal_customizations", [])
  portal_pages      = lookup(local.org_config, "portal_pages", [])
  portal_snippets   = lookup(local.org_config, "portal_snippets", [])
  portal_appearance = lookup(local.org_config, "portal_appearances", [])
  portal_logos      = lookup(local.org_config, "portal_logos", [])
  portal_favicons   = lookup(local.org_config, "portal_favicons", [])
  product_versions  = lookup(local.org_config, "portal_product_versions", [])
  dashboards        = lookup(local.org_config, "dashboards", [])

  apis_by_key = {
    for api in local.apis : "${api.name}:${lookup(api, "version", "")}" => api
  }

  # api_ids_by_name: keyed by both "name:version" and plain "name" (last version wins for plain key).
  # Plain-name keys allow api_specifications, api_implementations, api_documents, etc.
  # to reference an API by name without needing to know the version string.
  api_ids_by_name = merge(
    { for key, api in local.apis_by_key : key => module.apis[key].id },
    { for key, api in local.apis_by_key : api.name => module.apis[key].id }
  )

  inline_api_publications = flatten([
    for api_key, api in local.apis_by_key : [
      for portal in lookup(api, "portals", []) : {
        api_key                    = api_key
        api_name                   = api.name
        version                    = lookup(api, "version", "")
        portal_name                = lookup(portal, "name", null)
        portal_id                  = lookup(portal, "id", null)
        visibility                 = lookup(portal, "visibility", "private")
        auth_strategy_ids          = lookup(portal, "auth_strategy_ids", null)
        auto_approve_registrations = lookup(portal, "auto_approve_registrations", null)
      }
    ]
  ])

  api_publications_by_key = merge(
    {
      for publication in local.inline_api_publications :
      "${publication.api_key}:${coalesce(publication.portal_name, publication.portal_id)}" => publication
    },
    {
      for publication in local.api_publications :
      "${lookup(publication, "api_key", "${publication.api_name}:${lookup(publication, "version", "")}")}:${coalesce(lookup(publication, "portal_name", null), lookup(publication, "portal_id", null))}" => publication
    }
  )

  authentication_settings = lookup(local.org_config, "authentication_settings", null) == null ? [] : [local.org_config.authentication_settings]
  identity_providers = concat(
    lookup(local.org_config, "identity_providers", []),
    lookup(local.org_config, "identity_provider", null) == null ? [] : [local.org_config.identity_provider]
  )
  identity_provider_team_group_mappings = lookup(local.org_config, "identity_provider_team_group_mappings", lookup(local.org_config, "team_group_mappings", []))
  identity_provider_team_group_mappings_missing_team_ref = [
    for mapping in local.identity_provider_team_group_mappings : mapping
    if lookup(mapping, "team_name", null) == null && lookup(mapping, "team_id", null) == null
  ]
  identity_provider_team_group_mappings_unknown_team_names = [
    for mapping in local.identity_provider_team_group_mappings : lookup(mapping, "team_name", null)
    if lookup(mapping, "team_name", null) != null && !contains(keys(local.teams_by_name), lookup(mapping, "team_name", null))
  ]
  identity_provider_secret_violations = [
    for provider in local.identity_providers : lookup(provider, "name", lookup(provider, "idp_type", "identity-provider"))
    if can(provider.oidc_client_secret)
  ]
  portal_auth_secret_violations = [
    for auth in local.portal_auths : auth.portal_name
    if can(auth.oidc_client_secret)
  ]
  portal_customization_allowed_keys = toset(["portal_name", "css", "layout", "robots", "menu", "spec_renderer", "theme"])
  portal_customization_unsupported_keys = flatten([
    for customization in local.customizations : [
      for key in setsubtract(toset(keys(customization)), local.portal_customization_allowed_keys) :
      "${customization.portal_name}.${key}"
    ]
  ])

  entity_ids_by_type_and_name = {
    "Control Planes" = { for name, cp in module.control_planes : name => cp.control_plane.id }
    "APIs"           = local.api_ids_by_name
    "API Products"   = local.api_ids_by_name
    "Portals"        = { for name, portal in module.developer_portals : name => portal.id }
  }

  # ---------------------------------------------------------------------------
  # Extended entity locals (wired to modules below)
  # ---------------------------------------------------------------------------

  api_specifications  = lookup(local.org_config, "api_specifications", [])
  api_implementations = lookup(local.org_config, "api_implementations", [])

  system_account_teams = lookup(local.org_config, "system_account_teams", [])
  team_users_list      = lookup(local.org_config, "team_users", [])

  audit_log_config = lookup(local.org_config, "audit_log", null) == null ? [] : [local.org_config.audit_log]
  # Only include destinations whose authorization secret is available in sensitive_vars.
  # Destinations with a missing or empty authorization are silently skipped (e.g. local act runs).
  # nonsensitive() is safe: list items contain only non-secret YAML config (name, endpoint, etc.),
  # not the actual secret values; sensitive_vars is used only as a boolean predicate here.
  audit_log_destinations = nonsensitive([
    for dest in lookup(local.org_config, "audit_log_destinations", []) :
    dest if lookup(var.sensitive_vars, lookup(dest, "authorization_ref", "__unset__"), "") != ""
  ])

  realms                    = lookup(local.org_config, "realms", [])
  centralized_consumers     = lookup(local.org_config, "centralized_consumers", [])
  centralized_consumer_keys = lookup(local.org_config, "centralized_consumer_keys", [])

  cloud_gateway_networks            = lookup(local.org_config, "cloud_gateway_networks", [])
  cloud_gateway_configurations_list = lookup(local.org_config, "cloud_gateway_configurations", [])
  cloud_gateway_custom_domains_list = lookup(local.org_config, "cloud_gateway_custom_domains", [])
  cloud_gateway_transit_gateways    = lookup(local.org_config, "cloud_gateway_transit_gateways", [])
  cloud_gateway_private_dns_list    = lookup(local.org_config, "cloud_gateway_private_dns", [])

  integration_instances                 = lookup(local.org_config, "integration_instances", [])
  integration_instance_auth_configs     = lookup(local.org_config, "integration_instance_auth_configs", [])
  integration_instance_auth_credentials = lookup(local.org_config, "integration_instance_auth_credentials", [])

  mesh_control_planes       = lookup(local.org_config, "mesh_control_planes", [])
  portal_audit_log_webhooks = lookup(local.org_config, "portal_audit_log_webhooks", [])
  serverless_cloud_gateways = lookup(local.org_config, "serverless_cloud_gateways", [])
}

resource "terraform_data" "validate_org_config" {
  input = local.config_files

  lifecycle {
    precondition {
      condition     = length(local.sanitized_team_name_values) == length(distinct(local.sanitized_team_name_values))
      error_message = "Sanitized team names must be unique because they are used for system accounts and Vault paths."
    }

    precondition {
      condition     = !contains(local.sanitized_team_name_values, "")
      error_message = "Team names must contain at least one lowercase alphanumeric character after sanitization."
    }

    precondition {
      condition     = length(local.identity_provider_secret_violations) == 0
      error_message = "Identity provider YAML must not contain oidc_client_secret. Use oidc_client_secret_ref and pass the value via var.sensitive_vars."
    }

    precondition {
      condition     = length(local.portal_auth_secret_violations) == 0
      error_message = "Portal auth YAML must not contain oidc_client_secret. Use oidc_client_secret_ref and pass the value via var.sensitive_vars."
    }

    precondition {
      condition     = length(local.portal_customization_unsupported_keys) == 0
      error_message = "Unsupported portal_customizations keys found: ${join(", ", local.portal_customization_unsupported_keys)}."
    }

    precondition {
      condition     = length(local.identity_provider_team_group_mappings_missing_team_ref) == 0
      error_message = "Each identity provider team-group mapping must define either team_name or team_id."
    }

    precondition {
      condition     = length(local.identity_provider_team_group_mappings_unknown_team_names) == 0
      error_message = "Unknown team_name in identity provider team-group mappings: ${join(", ", local.identity_provider_team_group_mappings_unknown_team_names)}."
    }
  }
}

################################################################################
# STEP 1: CREATE CONTROL PLANES AND CONTROL PLANE GROUPS
################################################################################

module "control_planes" {
  source = "./modules/control_plane"

  for_each = local.all_control_planes

  name           = each.value.name
  description    = lookup(each.value, "description", null)
  cluster_type   = lookup(each.value, "cluster_type", "CLUSTER_TYPE_CONTROL_PLANE")
  auth_type      = lookup(each.value, "auth_type", null)
  cloud_gateway  = lookup(each.value, "cloud_gateway", false)
  proxy_urls     = lookup(each.value, "proxy_urls", [])
  labels         = lookup(each.value, "labels", {})
  plugins        = lookup(each.value, "plugins", {})
  vaults         = lookup(each.value, "vaults", [])
  custom_plugins = lookup(each.value, "custom_plugins", [])
  services       = lookup(each.value, "services", [])
  routes         = lookup(each.value, "routes", [])
  upstreams      = lookup(each.value, "upstreams", [])
  partials       = lookup(each.value, "partials", [])
  sensitive_vars = var.sensitive_vars
}

resource "konnect_gateway_control_plane_membership" "this" {
  for_each = {
    for membership in local.control_plane_memberships : membership.key => membership
  }

  id = module.control_planes[each.value.cp_name].control_plane.id

  members = [{
    id = module.control_planes[each.value.group_name].control_plane.id
  }]
}

################################################################################
# STEP 2: CREATE TEAMS, ROLES, AND TEAM SYSTEM ACCOUNTS
################################################################################

module "teams" {
  source = "./modules/team"

  for_each = { for team in local.teams : team.name => team }

  name        = each.value.name
  description = lookup(each.value, "description", null)
  labels      = merge(local.labels, lookup(each.value, "labels", {}))
}

module "team_roles" {
  source = "./modules/team_role"

  for_each = {
    for role in local.team_role_bindings :
    "${role.team_name}:${role.entity_type_name}:${role.role_name}:${role.entity_name}:${role.entity_region}" => role
    if role.role_name != null && role.entity_type_name != null
  }

  team_id          = module.teams[each.value.team_name].id
  entity_type_name = each.value.entity_type_name
  role_name        = each.value.role_name
  entity_id        = each.value.entity_name == "*" ? "*" : can(regex(local.uuid_pattern, each.value.entity_name)) ? each.value.entity_name : local.entity_ids_by_type_and_name[each.value.entity_type_name][each.value.entity_name]
  entity_region    = each.value.entity_region
}

module "team_system_accounts" {
  source = "./modules/team_system_account"

  for_each = module.teams

  team_name           = local.sanitized_team_names[each.key]
  team_id             = each.value.id
  expires_at          = lookup(local.teams_by_name[each.key], "system_account_token_expires_at", var.default_system_account_token_expires_at)
  control_plane_roles = lookup(local.team_system_account_control_plane_roles, each.key, [])
  api_roles           = lookup(local.team_system_account_api_roles, each.key, [])
  api_product_roles   = lookup(local.team_system_account_api_product_roles, each.key, [])
}

module "team_vault" {
  source = "./modules/team_vault"

  for_each = var.create_team_vault_secrets ? module.teams : {}

  team_name                  = local.sanitized_team_names[each.key]
  system_account_secret_path = "system-accounts/sa-${local.sanitized_team_names[each.key]}"
  system_account_token       = module.team_system_accounts[each.key].system_account_token
  github_organization        = var.github_organization
}

################################################################################
# STEP 3: CREATE EXPLICIT SYSTEM ACCOUNTS
################################################################################

module "system_account" {
  source = "./modules/system_account"

  for_each = { for account in local.system_accounts : account.name => account }

  name            = each.value.name
  description     = lookup(each.value, "description", null)
  konnect_managed = lookup(each.value, "konnect_managed", false)
}

module "system_account_role" {
  source = "./modules/system_account_role"

  for_each = {
    for role in local.system_account_role_bindings :
    "${role.account_name}:${role.entity_type_name}:${role.role_name}:${role.entity_name}:${role.entity_region}" => role
    if role.role_name != null && role.entity_type_name != null
  }

  account_id       = module.system_account[each.value.account_name].id
  entity_type_name = each.value.entity_type_name
  role_name        = each.value.role_name
  entity_id        = each.value.entity_name == "*" ? "*" : can(regex(local.uuid_pattern, each.value.entity_name)) ? each.value.entity_name : local.entity_ids_by_type_and_name[each.value.entity_type_name][each.value.entity_name]
  entity_region    = each.value.entity_region
}

module "system_account_access_token" {
  source = "./modules/system_account_access_token"

  for_each = { for account in local.system_accounts : account.name => account if lookup(account, "create_access_token", false) }

  account_id = module.system_account[each.key].id
  name       = lookup(each.value, "token_name", "${each.key}-token")
  expires_at = lookup(each.value, "token_expires_at", var.default_system_account_token_expires_at)
}

resource "vault_mount" "system_accounts" {
  for_each = var.create_system_account_vault_secrets && length(module.system_account_access_token) > 0 ? { this = true } : {}

  path        = var.system_account_vault_mount
  type        = "kv"
  options     = { version = "2" }
  description = "Vault mount for explicit Konnect system-account tokens"
}

resource "vault_kv_secret_v2" "system_account_tokens" {
  for_each = var.create_system_account_vault_secrets ? module.system_account_access_token : {}

  mount               = vault_mount.system_accounts["this"].path
  name                = "system-accounts/sa-${local.sanitized_system_account_names[each.key]}"
  delete_all_versions = true
  data_json = jsonencode({
    token = each.value.token
  })
  custom_metadata {
    max_versions = 5
  }
}

################################################################################
# STEP 4: CREATE APPLICATION AUTH STRATEGIES, PORTALS, AND PORTAL CONTENT
################################################################################

module "application_auth_strategy" {
  source = "./modules/application_auth_strategy"

  for_each = { for strategy in local.auth_strategies : strategy.name => strategy }

  name               = each.value.name
  display_name       = lookup(each.value, "display_name", null)
  labels             = merge(local.labels, lookup(each.value, "labels", {}))
  strategy_type      = lookup(each.value, "strategy_type", lookup(each.value, "type", "key_auth"))
  key_auth_key_names = try(each.value.config.key_names, lookup(each.value, "key_auth_key_names", []))

  oidc_dcr_provider_id       = lookup(each.value, "dcr_provider_id", null)
  oidc_additional_properties = try(each.value.config.additional_properties, null)
  oidc_auth_methods          = try(each.value.config.auth_methods, [])
  oidc_credential_claim      = try(each.value.config.credential_claim, [])
  oidc_issuer                = try(each.value.config.issuer, null)
  oidc_scopes                = try(each.value.config.scopes, [])
}

module "developer_portals" {
  source = "./modules/developer_portal"

  for_each = { for portal in local.portals : portal.name => portal }

  name                      = each.value.name
  description               = lookup(each.value, "description", null)
  display_name              = lookup(each.value, "display_name", null)
  labels                    = merge(local.labels, lookup(each.value, "labels", {}))
  authentication_enabled    = lookup(each.value, "authentication_enabled", null)
  auto_approve_applications = lookup(each.value, "auto_approve_applications", null)
  auto_approve_developers   = lookup(each.value, "auto_approve_developers", null)
  default_api_visibility    = lookup(each.value, "default_api_visibility", null)
  default_application_auth_strategy_id = try(
    module.application_auth_strategy[lookup(each.value, "default_application_auth_strategy_name", lookup(each.value, "default_application_auth_strategy", ""))].id,
    lookup(each.value, "default_application_auth_strategy_id", null)
  )
  default_page_visibility = lookup(each.value, "default_page_visibility", null)
  rbac_enabled            = lookup(each.value, "rbac_enabled", null)
  force_destroy           = lookup(each.value, "force_destroy", null)

  depends_on = [module.application_auth_strategy]
}

module "portal_custom_domains" {
  source = "./modules/portal_custom_domain"

  for_each = { for domain in local.portal_domains : "${domain.portal_name}:${domain.hostname}" => domain }

  portal_id                      = module.developer_portals[each.value.portal_name].id
  hostname                       = each.value.hostname
  enabled                        = lookup(each.value, "enabled", false)
  ssl_domain_verification_method = lookup(each.value, "ssl_domain_verification_method", "dns")
}

module "portal_teams" {
  source = "./modules/portal_team"

  for_each = { for team in local.portal_teams : "${team.portal_name}:${team.name}" => team }

  portal_id = module.developer_portals[each.value.portal_name].id
  name      = each.value.name
}

module "portal_auths" {
  source = "./modules/portal_auth"

  for_each = { for auth in local.portal_auths : auth.portal_name => auth }

  portal_id                 = module.developer_portals[each.value.portal_name].id
  basic_auth_enabled        = lookup(each.value, "basic_auth_enabled", null)
  oidc_auth_enabled         = lookup(each.value, "oidc_auth_enabled", null)
  saml_auth_enabled         = lookup(each.value, "saml_auth_enabled", null)
  idp_mapping_enabled       = lookup(each.value, "idp_mapping_enabled", null)
  konnect_mapping_enabled   = lookup(each.value, "konnect_mapping_enabled", null)
  oidc_team_mapping_enabled = lookup(each.value, "oidc_team_mapping_enabled", null)
  oidc_issuer               = lookup(each.value, "oidc_issuer", null)
  oidc_client_id            = lookup(each.value, "oidc_client_id", null)
  oidc_client_secret        = lookup(var.sensitive_vars, lookup(each.value, "oidc_client_secret_ref", "portal_oidc_client_secret"), null)
  oidc_scopes               = lookup(each.value, "oidc_scopes", [])
  oidc_claim_mappings       = lookup(each.value, "oidc_claim_mappings", null)
}

module "portal_customizations" {
  source = "./modules/portal_customization"

  for_each = { for customization in local.customizations : customization.portal_name => customization }

  portal_id     = module.developer_portals[each.value.portal_name].id
  css           = lookup(each.value, "css", null)
  layout        = lookup(each.value, "layout", null)
  robots        = lookup(each.value, "robots", null)
  menu          = lookup(each.value, "menu", null)
  spec_renderer = lookup(each.value, "spec_renderer", null)
  theme         = lookup(each.value, "theme", null)
}

module "portal_pages" {
  source = "./modules/portal_page"

  for_each = { for page in local.portal_pages : "${page.portal_name}:${page.slug}" => page }

  portal_id      = module.developer_portals[each.value.portal_name].id
  slug           = each.value.slug
  content        = each.value.content
  title          = lookup(each.value, "title", null)
  description    = lookup(each.value, "description", null)
  parent_page_id = lookup(each.value, "parent_page_id", null)
  status         = lookup(each.value, "status", null)
  visibility     = lookup(each.value, "visibility", null)
}

module "portal_snippets" {
  source = "./modules/portal_snippet"

  for_each = { for snippet in local.portal_snippets : "${snippet.portal_name}:${snippet.name}" => snippet }

  portal_id   = module.developer_portals[each.value.portal_name].id
  name        = each.value.name
  content     = each.value.content
  title       = lookup(each.value, "title", null)
  description = lookup(each.value, "description", null)
  status      = lookup(each.value, "status", null)
  visibility  = lookup(each.value, "visibility", null)
}

module "portal_appearances" {
  source = "./modules/portal_appearance"

  for_each = { for appearance in local.portal_appearance : appearance.portal_name => appearance }

  portal_id        = module.developer_portals[each.value.portal_name].id
  theme_name       = lookup(each.value, "theme_name", null)
  use_custom_fonts = lookup(each.value, "use_custom_fonts", null)
  custom_fonts     = lookup(each.value, "custom_fonts", null)
  custom_theme     = lookup(each.value, "custom_theme", null)
  images           = lookup(each.value, "images", null)
  text             = lookup(each.value, "text", null)
}

module "portal_logos" {
  source = "./modules/portal_logo"

  for_each = { for logo in local.portal_logos : logo.portal_name => logo }

  portal_id = module.developer_portals[each.value.portal_name].id
  data      = each.value.data
}

module "portal_favicons" {
  source = "./modules/portal_favicon"

  for_each = { for favicon in local.portal_favicons : favicon.portal_name => favicon }

  portal_id = module.developer_portals[each.value.portal_name].id
  data      = each.value.data
}

module "portal_product_versions" {
  source = "./modules/portal_product_version"

  for_each = {
    for version in local.product_versions :
    "${version.portal_name}:${lookup(version, "api_name", "")}:${lookup(version, "version", lookup(version, "product_version_id", ""))}" => version
  }

  portal_id = module.developer_portals[each.value.portal_name].id
  product_version_id = (
    lookup(each.value, "api_name", null) != null
    ? module.api_versions["${each.value.api_name}:${lookup(each.value, "version", "")}"].id
    : each.value.product_version_id
  )
  publish_status                   = each.value.publish_status
  application_registration_enabled = each.value.application_registration_enabled
  auto_approve_registration        = each.value.auto_approve_registration
  deprecated                       = each.value.deprecated
  auth_strategy_ids                = lookup(each.value, "auth_strategy_ids", [])
  notify_developers                = lookup(each.value, "notify_developers", null)

  depends_on = [module.api_versions]
}

module "dashboards" {
  source = "./modules/dashboard"

  providers = {
    konnect-beta = konnect-beta
  }

  for_each = {
    for dashboard in local.dashboards :
    coalesce(lookup(dashboard, "slug", null), dashboard.name) => dashboard
  }

  name       = each.value.name
  labels     = merge(local.labels, lookup(each.value, "labels", {}))
  definition = each.value.definition

  depends_on = [module.developer_portals]
}

################################################################################
# STEP 5: CREATE APIS AND PORTAL PUBLICATIONS
################################################################################

module "apis" {
  source = "./modules/api"

  for_each = local.apis_by_key

  name         = each.value.name
  description  = lookup(each.value, "description", null)
  labels       = merge(local.labels, lookup(each.value, "labels", {}))
  slug         = lookup(each.value, "slug", null)
  spec_content = try(file("${var.gh_workspace_path}/${each.value.spec_content.file}"), try(each.value.spec_content.content, null))
  api_version  = lookup(each.value, "version", null)
}

module "api_versions" {
  source = "./modules/api_version"

  for_each = {
    for version in local.api_versions :
    "${coalesce(lookup(version, "api_id", null), lookup(version, "api_name", null))}:${lookup(version, "version", "")}" => version
  }

  api_id       = try(local.api_ids_by_name[lookup(each.value, "api_key", each.value.api_name)], each.value.api_id)
  api_version  = lookup(each.value, "version", null)
  spec_content = try(file("${var.gh_workspace_path}/${each.value.spec_content.file}"), each.value.spec_content.content)
}

module "api_documents" {
  source = "./modules/api_document"

  for_each = { for doc in local.api_documents : "${doc.api_name}:${lookup(doc, "version", "")}:${doc.slug}" => doc }

  api_id             = try(local.api_ids_by_name[lookup(each.value, "api_key", "${each.value.api_name}:${lookup(each.value, "version", "")}")], local.api_ids_by_name[each.value.api_name])
  content            = try(file("${var.gh_workspace_path}/${each.value.content.file}"), each.value.content)
  parent_document_id = lookup(each.value, "parent_document_id", null)
  slug               = each.value.slug
  status             = lookup(each.value, "status", "unpublished")
  title              = lookup(each.value, "title", null)
}

module "api_publications" {
  source = "./modules/api_publication"

  for_each = local.api_publications_by_key

  api_id                     = try(local.api_ids_by_name[lookup(each.value, "api_key", "${each.value.api_name}:${lookup(each.value, "version", "")}")], local.api_ids_by_name[each.value.api_name])
  portal_id                  = try(module.developer_portals[each.value.portal_name].id, lookup(each.value, "portal_id", null))
  auth_strategy_ids          = try(length(lookup(each.value, "auth_strategy_ids", [])) > 0 ? lookup(each.value, "auth_strategy_ids", null) : null, null)
  auto_approve_registrations = lookup(each.value, "auto_approve_registrations", null)
  visibility                 = lookup(each.value, "visibility", "private")
}

################################################################################
# STEP 6: CREATE AUTHENTICATION AND IDENTITY CONFIGURATION
################################################################################

module "authentication_settings" {
  source = "./modules/authentication_settings"

  for_each = length(local.authentication_settings) > 0 ? { singleton = local.authentication_settings[0] } : {}

  basic_auth_enabled      = lookup(each.value, "basic_auth_enabled", null)
  idp_mapping_enabled     = lookup(each.value, "idp_mapping_enabled", null)
  konnect_mapping_enabled = lookup(each.value, "konnect_mapping_enabled", null)
  oidc_auth_enabled       = lookup(each.value, "oidc_auth_enabled", null)
  saml_auth_enabled       = lookup(each.value, "saml_auth_enabled", null)
}

module "identity_providers" {
  source = "./modules/identity_provider"

  for_each = { for provider in local.identity_providers : coalesce(lookup(provider, "name", null), lookup(provider, "idp_type", lookup(provider, "type", "identity-provider"))) => provider }

  enabled               = lookup(each.value, "enabled", null)
  login_path            = lookup(each.value, "login_path", null)
  idp_type              = lookup(each.value, "idp_type", lookup(each.value, "type", null))
  oidc_issuer_url       = try(each.value.oidc_issuer_url, each.value.config.issuer_url)
  oidc_client_id        = try(each.value.oidc_client_id, lookup(var.sensitive_vars, "idp_client_id", null))
  oidc_client_secret    = lookup(var.sensitive_vars, lookup(each.value, "oidc_client_secret_ref", "idp_client_secret"), null)
  oidc_scopes           = try(each.value.oidc_scopes, each.value.config.scopes)
  oidc_claim_email      = try(each.value.oidc_claim_mappings.email, each.value.config.claim_mappings.email)
  oidc_claim_groups     = try(each.value.oidc_claim_mappings.groups, each.value.config.claim_mappings.groups)
  oidc_claim_name       = try(each.value.oidc_claim_mappings.name, each.value.config.claim_mappings.name)
  saml_idp_metadata_url = lookup(each.value, "saml_idp_metadata_url", null)
  saml_idp_metadata_xml = lookup(each.value, "saml_idp_metadata_xml", null)
}

module "identity_provider_team_group_mappings" {
  source = "./modules/identity_provider_team_group_mapping"

  for_each = {
    for mapping in local.identity_provider_team_group_mappings :
    "${coalesce(lookup(mapping, "identity_provider_name", null), lookup(mapping, "identity_provider_id", "default"))}:${mapping.group}" => mapping
  }

  group = each.value.group
  identity_provider_id = (
    lookup(each.value, "identity_provider_name", null) != null
    ? try(module.identity_providers[lookup(each.value, "identity_provider_name", null)].id, null)
    : try(
      coalesce(
        lookup(each.value, "identity_provider_id", null),
        try(module.identity_providers[local.identity_providers[0].name].id, null)
      ),
      null
    )
  )
  team_id = (
    lookup(each.value, "team_name", null) != null
    ? try(module.teams[each.value.team_name].id, null)
    : lookup(each.value, "team_id", null)
  )

  depends_on = [module.identity_providers, module.teams]
}

################################################################################
# STEP 7: EXTENDED ENTITIES
################################################################################

module "api_specifications" {
  source = "./modules/api_specification"

  for_each = {
    for spec in local.api_specifications :
    lookup(spec, "api_name", lookup(spec, "api_id", "")) => spec
  }

  api_id  = try(local.api_ids_by_name[each.value.api_name], each.value.api_id)
  content = each.value.content
  type    = lookup(each.value, "type", null)

  depends_on = [module.apis]
}

module "api_implementations" {
  source = "./modules/api_implementation"

  for_each = {
    for impl in local.api_implementations :
    lookup(impl, "api_name", lookup(impl, "api_id", "")) => impl
  }

  api_id = try(local.api_ids_by_name[each.value.api_name], each.value.api_id)
  service = {
    control_plane_id = (
      lookup(each.value.service, "control_plane_name", null) != null
      ? module.control_planes[each.value.service.control_plane_name].control_plane.id
      : each.value.service.control_plane_id
    )
    id = each.value.service.id
  }

  depends_on = [module.apis, module.control_planes]
}

module "system_account_teams" {
  source = "./modules/system_account_team"

  for_each = {
    for st in local.system_account_teams :
    "${st.account_name}:${st.team_name}" => st
  }

  account_id = module.system_account[each.value.account_name].id
  team_id    = module.teams[each.value.team_name].id

  depends_on = [module.system_account, module.teams]
}

module "team_users" {
  source = "./modules/team_user"

  for_each = {
    for tu in local.team_users_list :
    "${tu.team_name}:${tu.user_id}" => tu
  }

  team_id = module.teams[each.value.team_name].id
  user_id = each.value.user_id

  depends_on = [module.teams]
}

module "audit_log" {
  source = "./modules/audit_log"

  # Only provision when the authorization secret is available in sensitive_vars.
  # Skips gracefully in local act runs where TF_SENSITIVE_VARS is empty.
  # nonsensitive() is safe: we expose only a boolean (present/absent), not the secret value.
  for_each = (
    length(local.audit_log_config) > 0 &&
    nonsensitive(lookup(var.sensitive_vars, lookup(try(local.audit_log_config[0], {}), "authorization_ref", "audit_log_authorization"), "")) != ""
  ) ? { singleton = local.audit_log_config[0] } : {}

  endpoint              = lookup(each.value, "endpoint", null)
  authorization         = lookup(var.sensitive_vars, lookup(each.value, "authorization_ref", "audit_log_authorization"), null)
  enabled               = lookup(each.value, "enabled", null)
  log_format            = lookup(each.value, "log_format", null)
  skip_ssl_verification = lookup(each.value, "skip_ssl_verification", null)
}

module "audit_log_destinations" {
  source = "./modules/audit_log_destination"

  for_each = { for dest in local.audit_log_destinations : dest.name => dest }

  name                  = each.value.name
  endpoint              = each.value.endpoint
  authorization         = lookup(var.sensitive_vars, lookup(each.value, "authorization_ref", "audit_log_authorization"), null)
  log_format            = lookup(each.value, "log_format", null)
  skip_ssl_verification = lookup(each.value, "skip_ssl_verification", null)
}

module "realms" {
  source = "./modules/realm"

  for_each = { for r in local.realms : r.name => r }

  name                     = each.value.name
  allow_all_control_planes = lookup(each.value, "allow_all_control_planes", null)
  allowed_control_planes = [
    for name in lookup(each.value, "allowed_control_plane_names", lookup(each.value, "allowed_control_planes", [])) :
    can(module.control_planes[name].control_plane.id) ? module.control_planes[name].control_plane.id : name
  ]
  consumer_groups = lookup(each.value, "consumer_groups", [])
  ttl             = lookup(each.value, "ttl", null)
  negative_ttl    = lookup(each.value, "negative_ttl", null)
  force_destroy   = lookup(each.value, "force_destroy", null)
}

module "centralized_consumers" {
  source = "./modules/centralized_consumer"

  for_each = {
    for c in local.centralized_consumers :
    "${coalesce(lookup(c, "realm_name", null), lookup(c, "realm_id", ""))}:${c.username}" => c
  }

  realm_id = (
    lookup(each.value, "realm_name", null) != null
    ? module.realms[each.value.realm_name].id
    : each.value.realm_id
  )
  username        = each.value.username
  custom_id       = lookup(each.value, "custom_id", null)
  consumer_type   = lookup(each.value, "consumer_type", null)
  consumer_groups = lookup(each.value, "consumer_groups", [])
  tags            = lookup(each.value, "tags", [])

  depends_on = [module.realms]
}

module "centralized_consumer_keys" {
  source = "./modules/centralized_consumer_key"

  for_each = {
    for k in local.centralized_consumer_keys :
    "${coalesce(lookup(k, "realm_name", null), lookup(k, "realm_id", ""))}:${coalesce(lookup(k, "consumer_username", null), lookup(k, "consumer_id", ""))}" => k
  }

  realm_id = (
    lookup(each.value, "realm_name", null) != null
    ? module.realms[each.value.realm_name].id
    : each.value.realm_id
  )
  consumer_id = (
    lookup(each.value, "consumer_username", null) != null
    ? module.centralized_consumers["${coalesce(lookup(each.value, "realm_name", null), each.value.realm_id)}:${each.value.consumer_username}"].id
    : each.value.consumer_id
  )
  key_type = lookup(each.value, "key_type", null)
  tags     = lookup(each.value, "tags", [])

  depends_on = [module.centralized_consumers]
}

module "cloud_gateway_networks" {
  source = "./modules/cloud_gateway_network"

  for_each = { for n in local.cloud_gateway_networks : n.name => n }

  name                              = each.value.name
  region                            = each.value.region
  cidr_block                        = each.value.cidr_block
  availability_zones                = each.value.availability_zones
  cloud_gateway_provider_account_id = each.value.cloud_gateway_provider_account_id
}

module "cloud_gateway_configurations" {
  source = "./modules/cloud_gateway_configuration"

  for_each = {
    for c in local.cloud_gateway_configurations_list :
    "${coalesce(lookup(c, "control_plane_name", null), lookup(c, "control_plane_id", ""))}:${c.control_plane_geo}" => c
  }

  control_plane_id = (
    lookup(each.value, "control_plane_name", null) != null
    ? module.control_planes[each.value.control_plane_name].control_plane.id
    : each.value.control_plane_id
  )
  control_plane_geo = each.value.control_plane_geo
  dataplane_groups = [
    for dg in each.value.dataplane_groups : merge(
      { for k, v in dg : k => v if k != "network_name" },
      {
        network_id = (
          lookup(dg, "network_name", null) != null
          ? module.cloud_gateway_networks[dg.network_name].id
          : dg.network_id
        )
      }
    )
  ]
  config_version = each.value.config_version

  depends_on = [module.control_planes, module.cloud_gateway_networks]
}

module "cloud_gateway_custom_domains" {
  source = "./modules/cloud_gateway_custom_domain"

  for_each = {
    for d in local.cloud_gateway_custom_domains_list :
    "${coalesce(lookup(d, "control_plane_name", null), lookup(d, "control_plane_id", ""))}:${d.domain}" => d
  }

  control_plane_id = (
    lookup(each.value, "control_plane_name", null) != null
    ? module.control_planes[each.value.control_plane_name].control_plane.id
    : each.value.control_plane_id
  )
  control_plane_geo = each.value.control_plane_geo
  domain            = each.value.domain

  depends_on = [module.control_planes]
}

module "cloud_gateway_transit_gateways" {
  source = "./modules/cloud_gateway_transit_gateway"

  for_each = {
    for tg in local.cloud_gateway_transit_gateways :
    coalesce(lookup(tg, "network_name", null), lookup(tg, "network_id", "")) => tg
  }

  network_id = (
    lookup(each.value, "network_name", null) != null
    ? module.cloud_gateway_networks[each.value.network_name].id
    : each.value.network_id
  )
  aws_transit_gateway             = lookup(each.value, "aws_transit_gateway", null)
  aws_vpc_peering_gateway         = lookup(each.value, "aws_vpc_peering_gateway", null)
  azure_transit_gateway           = lookup(each.value, "azure_transit_gateway", null)
  gcp_vpc_peering_transit_gateway = lookup(each.value, "gcp_vpc_peering_transit_gateway", null)

  depends_on = [module.cloud_gateway_networks]
}

module "cloud_gateway_private_dns" {
  source = "./modules/cloud_gateway_private_dns"

  for_each = {
    for dns in local.cloud_gateway_private_dns_list :
    "${coalesce(lookup(dns, "network_name", null), lookup(dns, "network_id", ""))}:${lookup(dns, "name", "default")}" => dns
  }

  network_id = (
    lookup(each.value, "network_name", null) != null
    ? module.cloud_gateway_networks[each.value.network_name].id
    : each.value.network_id
  )
  name                          = lookup(each.value, "name", null)
  private_dns_attachment_config = lookup(each.value, "private_dns_attachment_config", null)

  depends_on = [module.cloud_gateway_networks]
}

module "integration_instances" {
  source = "./modules/integration_instance"

  for_each = { for i in local.integration_instances : i.name => i }

  name             = each.value.name
  display_name     = each.value.display_name
  integration_name = each.value.integration_name
  description      = lookup(each.value, "description", null)
  config           = each.value.config
}

module "integration_instance_auth_configs" {
  source = "./modules/integration_instance_auth_config"

  for_each = {
    for c in local.integration_instance_auth_configs :
    c.integration_instance_name => c
  }

  integration_instance_id = module.integration_instances[each.value.integration_instance_name].id
  oauth_config            = lookup(each.value, "oauth_config", null)

  depends_on = [module.integration_instances]
}

module "integration_instance_auth_credentials" {
  source = "./modules/integration_instance_auth_credential"

  for_each = {
    for c in local.integration_instance_auth_credentials :
    c.integration_instance_name => c
  }

  integration_instance_id = module.integration_instances[each.value.integration_instance_name].id
  multi_key_auth          = lookup(each.value, "multi_key_auth", null)

  depends_on = [module.integration_instances]
}

module "mesh_control_planes" {
  source = "./modules/mesh_control_plane"

  for_each = { for m in local.mesh_control_planes : m.name => m }

  name        = each.value.name
  description = lookup(each.value, "description", null)
  labels      = lookup(each.value, "labels", {})
  features    = lookup(each.value, "features", [])
}

module "portal_audit_log_webhooks" {
  source = "./modules/portal_audit_log_webhook"

  for_each = {
    for w in local.portal_audit_log_webhooks :
    w.portal_name => w
  }

  portal_id = (
    lookup(each.value, "portal_name", null) != null
    ? try(module.developer_portals[each.value.portal_name].id, null)
    : each.value.portal_id
  )
  audit_log_destination_id = (
    lookup(each.value, "audit_log_destination_name", null) != null
    ? try(module.audit_log_destinations[each.value.audit_log_destination_name].id, null)
    : lookup(each.value, "audit_log_destination_id", null)
  )
  enabled = lookup(each.value, "enabled", null)

  depends_on = [module.developer_portals, module.audit_log_destinations]
}

module "serverless_cloud_gateways" {
  source = "./modules/serverless_cloud_gateway"

  for_each = {
    for s in local.serverless_cloud_gateways :
    coalesce(lookup(s, "control_plane_name", null), lookup(s, "control_plane_id", "")) => s
  }

  cluster_cert     = each.value.cluster_cert
  cluster_cert_key = lookup(var.sensitive_vars, lookup(each.value, "cluster_cert_key_ref", ""), lookup(each.value, "cluster_cert_key", null))
  control_plane_id = (
    lookup(each.value, "control_plane_name", null) != null
    ? module.control_planes[each.value.control_plane_name].control_plane.id
    : each.value.control_plane_id
  )
  control_plane_prefix = each.value.control_plane_prefix
  control_plane_region = each.value.control_plane_region
  labels               = lookup(each.value, "labels", {})

  depends_on = [module.control_planes]
}
