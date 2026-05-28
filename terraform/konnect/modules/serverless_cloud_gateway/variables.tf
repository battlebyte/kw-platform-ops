variable "cluster_cert" {
  description = "The cluster certificate (public key PEM). Requires replacement if changed."
  type        = string
}

variable "cluster_cert_key" {
  description = "The cluster certificate key (private key PEM). Sensitive. Requires replacement if changed."
  type        = string
  sensitive   = true
}

variable "control_plane_id" {
  description = "ID of the serverless cloud gateway control plane. Requires replacement if changed."
  type        = string
}

variable "control_plane_prefix" {
  description = "The prefix of the serverless cloud gateway CP. Requires replacement if changed."
  type        = string
}

variable "control_plane_region" {
  description = "The control plane region (us|eu|au). Requires replacement if changed."
  type        = string
}

variable "labels" {
  description = "Labels for tagged search. Keys must be 1-63 chars, cannot start with 'kong'/'konnect'/'mesh'/'kic'/'_'. Requires replacement if changed."
  type        = map(string)
  default     = {}
}
