output "config_files" {
  description = "Org YAML files loaded by the unified Konnect root."
  value       = local.config_files
}

output "control_planes" {
  description = "Control planes created by name."
  value       = { for name, cp in module.control_planes : name => cp.control_plane }
}

output "teams" {
  description = "Konnect teams created by name."
  value       = { for name, team in module.teams : name => { id = team.id, name = team.name } }
}

output "portals" {
  description = "Developer portals created by name."
  value       = { for name, portal in module.developer_portals : name => portal.id }
}

output "apis" {
  description = "APIs created by name and version key."
  value       = { for name, api in module.apis : name => api.id }
}
