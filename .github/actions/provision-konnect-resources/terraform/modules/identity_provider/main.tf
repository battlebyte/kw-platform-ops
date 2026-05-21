terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
  }
}

resource "konnect_identity_provider" "this" {
  enabled    = var.enabled
  login_path = var.login_path
  type       = var.idp_type

  config = (
    var.oidc_issuer_url != null ||
    var.saml_idp_metadata_url != null ||
    var.saml_idp_metadata_xml != null
    ) ? {
    oidc_identity_provider_config = var.oidc_issuer_url != null ? {
      issuer_url    = var.oidc_issuer_url
      client_id     = var.oidc_client_id
      client_secret = var.oidc_client_secret
      scopes        = length(coalesce(var.oidc_scopes, [])) > 0 ? var.oidc_scopes : null
      claim_mappings = (
        var.oidc_claim_email != null ||
        var.oidc_claim_groups != null ||
        var.oidc_claim_name != null
        ) ? {
        email  = var.oidc_claim_email
        groups = var.oidc_claim_groups
        name   = var.oidc_claim_name
      } : null
    } : null
    saml_identity_provider_config = (
      var.saml_idp_metadata_url != null || var.saml_idp_metadata_xml != null
      ) ? {
      idp_metadata_url = var.saml_idp_metadata_url
      idp_metadata_xml = var.saml_idp_metadata_xml
    } : null
  } : null
}
