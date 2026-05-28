variable "api_id" {
  description = "The ID of the API resource this implementation belongs to"
  type        = string
}

variable "service" {
  description = "The backend Gateway service to route to"
  type = object({
    control_plane_id = string
    id               = string
  })
}
