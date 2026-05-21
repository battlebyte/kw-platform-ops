variable "basic_auth_enabled" {
  description = "Whether basic auth is enabled for the organization."
  type        = bool
  default     = null
}

variable "idp_mapping_enabled" {
  description = "Whether IdP groups determine the Konnect teams a user has."
  type        = bool
  default     = null
}

variable "konnect_mapping_enabled" {
  description = "Whether a Konnect Identity Admin assigns teams to a user."
  type        = bool
  default     = null
}

variable "oidc_auth_enabled" {
  description = "Whether OIDC auth is enabled for the organization."
  type        = bool
  default     = null
}

variable "saml_auth_enabled" {
  description = "Whether SAML auth is enabled for the organization."
  type        = bool
  default     = null
}
