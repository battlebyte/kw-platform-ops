variable "group" {
  description = "The identity provider group name. Group names are case sensitive."
  type        = string
}

variable "identity_provider_id" {
  description = "ID of the identity provider."
  type        = string
}

variable "team_id" {
  description = "The Konnect team ID to associate with the identity provider group."
  type        = string
}
