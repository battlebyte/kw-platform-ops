variable "name" {
  description = "Control Plane name"
  type        = string
}

variable "description" {
  description = "Control Plane description"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to the Control Plane"
  type        = map(string)
  default     = {}
}

variable "cluster_type" {
  description = "Konnect Gateway cluster type."
  type        = string
  default     = "CLUSTER_TYPE_CONTROL_PLANE"
}

variable "auth_type" {
  description = "Authentication type for data planes."
  type        = string
  default     = null
}

variable "cloud_gateway" {
  description = "Whether this control plane is a Konnect Cloud Gateway"
  type        = bool
  default     = false
}

variable "team" {
  description = "Deprecated compatibility input. Team-scoped Vault writes are intentionally not handled by this module."
  type        = any
  default     = null
}

variable "proxy_urls" {
  description = "Proxy URLs for regular control planes."
  type = list(object({
    host     = string
    port     = number
    protocol = string
  }))
  default = []
}

variable "plugins" {
  description = "Global gateway plugins to apply to the control plane."
  type        = any
  default     = {}
}

variable "custom_plugins" {
  description = "Custom plugins to apply to the control plane."
  type        = any
  default     = []
}

variable "vaults" {
  description = "Kong gateway vaults to create for the control plane."
  type        = any
  default     = []
}

variable "sensitive_vars" {
  description = "Sensitive values for __variable__ substitution in gateway vault configs."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "services" {
  description = "Kong Gateway services with optional nested routes and plugins."
  type        = any
  default     = []
}

variable "routes" {
  description = "Standalone Kong Gateway routes."
  type        = any
  default     = []
}

variable "upstreams" {
  description = "Kong Gateway upstreams and targets."
  type        = any
  default     = []
}

variable "partials" {
  description = "Kong Gateway partials."
  type        = any
  default     = []
}
