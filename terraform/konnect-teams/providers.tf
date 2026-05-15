# provider "konnect" {
#   konnect_access_token = var.konnect_token
#   server_url           = var.konnect_server_url
# }

# provider "vault" {
#   address = var.vault_address
#   token   = var.vault_token
# }
provider "aws" {
  region = "eu-central-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  dynamic "endpoints" {
    for_each = var.s3_endpoint != "" ? [var.s3_endpoint] : []
    content {
      s3 = endpoints.value
    }
  }
}