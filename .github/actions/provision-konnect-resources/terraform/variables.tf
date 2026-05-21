// variables.tf
variable "environment" {
  description = "The environment to run"
  type        = string
  default     = "local"
}

variable "konnect_access_token" {
  description = "The Konnect Token to use for API requests"
  type        = string
}

variable "konnect_server_url" {
  description = "The URL of the Konnect server to connect to"
  type        = string
}

variable "konnect_region" {
  description = "The region to create the resources in"
  default     = "eu"
  type        = string
}

variable "org" {
  description = "Konnect organisation name — selects the subdirectory under config_dir"
  type        = string
  default     = "konnect"
}

variable "config_dir" {
  description = "Path to the directory containing org YAML config files"
  type        = string
}

variable "gh_workspace_path" {
  description = "The GitHub workspace path"
  type        = string
  default     = ""
}
