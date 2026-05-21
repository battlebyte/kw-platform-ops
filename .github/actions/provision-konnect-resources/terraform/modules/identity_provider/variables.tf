variable "enabled" {
  description = "Indicates whether the identity provider is enabled. Only one can be active at a time."
  type        = bool
  default     = null
}

variable "login_path" {
  description = "The path used for initiating login requests with the identity provider."
  type        = string
  default     = null
}

variable "idp_type" {
  description = "Specifies the type of identity provider. One of: oidc, saml. Requires replacement if changed."
  type        = string
  default     = null
}

# OIDC configuration
variable "oidc_issuer_url" {
  description = "The issuer URI of the OIDC identity provider."
  type        = string
  default     = null
}

variable "oidc_client_id" {
  description = "The client ID assigned by the OIDC identity provider."
  type        = string
  default     = null
}

variable "oidc_client_secret" {
  description = "The client secret assigned by the OIDC identity provider."
  type        = string
  sensitive   = true
  default     = null
}

variable "oidc_scopes" {
  description = "The scopes requested when authenticating with the OIDC identity provider."
  type        = list(string)
  default     = null
}

variable "oidc_claim_email" {
  description = "Claim mapping for the user email address."
  type        = string
  default     = null
}

variable "oidc_claim_groups" {
  description = "Claim mapping for the user group membership."
  type        = string
  default     = null
}

variable "oidc_claim_name" {
  description = "Claim mapping for the user name."
  type        = string
  default     = null
}

# SAML configuration
variable "saml_idp_metadata_url" {
  description = "The SAML identity provider metadata URL."
  type        = string
  default     = null
}

variable "saml_idp_metadata_xml" {
  description = "The SAML identity provider metadata XML. Use instead of saml_idp_metadata_url when the IdP does not expose a metadata URL."
  type        = string
  default     = null
}
