variable "team_name" {
  description = "Sanitised team name (lowercase, hyphens)"
  type        = string
}

variable "team_id" {
  description = "Konnect team ID"
  type        = string
}

variable "expires_at" {
  description = "Stable expiry timestamp for the generated team system-account access token."
  type        = string
}

variable "control_plane_roles" {
  description = "List of control plane role assignments for the team system account"
  type = list(object({
    entity_id = string
    region    = string
    role      = string
  }))
  default = []
}

variable "api_roles" {
  description = "List of API role assignments for the team system account"
  type = list(object({
    entity_id = string
    region    = string
    role      = string
  }))
  default = []
}

variable "api_product_roles" {
  description = "List of API Product role assignments for the team system account"
  type = list(object({
    entity_id = string
    region    = string
    role      = string
  }))
  default = []
}
