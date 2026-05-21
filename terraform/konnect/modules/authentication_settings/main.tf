terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_authentication_settings" "this" {
  basic_auth_enabled      = var.basic_auth_enabled
  idp_mapping_enabled     = var.idp_mapping_enabled
  konnect_mapping_enabled = var.konnect_mapping_enabled
  oidc_auth_enabled       = var.oidc_auth_enabled
  saml_auth_enabled       = var.saml_auth_enabled
}
