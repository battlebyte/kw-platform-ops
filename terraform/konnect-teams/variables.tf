// variables.tf
variable "konnect_region" {
  description = "The region to create the resources in"
  default     = "eu"
  type        = string
}

variable "resources_path" {
  description = "Path to the resources directory"
  type        = string
}

variable "create_team_buckets" {
  description = "Whether to create per-team S3 state buckets. Enable only for AWS S3 backend runs; leave false for MinIO."
  type        = bool
  default     = false
}

variable "s3_endpoint" {
  description = "Custom S3 endpoint for the aws provider. Set to the MinIO URL when using the MinIO backend; leave empty for real AWS."
  type        = string
  default     = ""
}
