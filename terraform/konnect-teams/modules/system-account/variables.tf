variable "team_name" {
  description = "The name of the team"
  type        = string
}

variable "team_id" {
  description = "The ID of the team"
  type        = string
}

variable "control_plane_roles" {
  description = "List of control plane role assignments for the team's system account. Each entry specifies a role (e.g. Admin, Creator, Viewer, Deployer), the entity_id (a specific control plane ID or '*' for all), and the region."
  type = list(object({
    entity_id = string
    region    = string
    role      = string
  }))
  default = []
}

variable "api_roles" {
  description = "List of API role assignments for the team's system account. Each entry specifies a role (e.g. Creator, Viewer, Publisher), the entity_id (a specific API ID or '*' for all), and the region."
  type = list(object({
    entity_id = string
    region    = string
    role      = string
  }))
  default = []
}

variable "api_product_roles" {
  description = "List of API Product role assignments for the team's system account. Each entry specifies a role (e.g. Creator, Viewer), the entity_id (a specific API Product ID or '*' for all), and the region."
  type = list(object({
    entity_id = string
    region    = string
    role      = string
  }))
  default = []
}
