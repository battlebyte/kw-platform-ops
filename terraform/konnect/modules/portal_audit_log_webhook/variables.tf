variable "portal_id" {
  description = "The Portal ID to attach the audit log webhook to"
  type        = string
}

variable "audit_log_destination_id" {
  description = "ID of the audit log destination to fan out portal events to"
  type        = string
  default     = null
}

variable "enabled" {
  description = "Whether the webhook is active. Default: false"
  type        = bool
  default     = null
}
