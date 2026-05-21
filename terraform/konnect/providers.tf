terraform {
  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "3.17.0"
    }
    konnect-beta = {
      source  = "Kong/konnect-beta"
      version = "0.17.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "4.4.0"
    }
  }
}

provider "konnect" {
  konnect_access_token = local.konnect_token
  server_url           = var.konnect_server_url
}

provider "konnect-beta" {
  konnect_access_token = local.konnect_token
  server_url           = var.konnect_server_url
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}
