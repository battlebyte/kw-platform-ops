variable "name" {
  description = "The name of the Mesh Control Plane"
  type        = string
}

variable "description" {
  description = "Description of the Mesh Control Plane"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to facilitate tagged search. Keys must be 1-63 characters."
  type        = map(string)
  default     = {}
}

variable "features" {
  description = "Feature flags for the Mesh Control Plane (requires replacement if changed)."
  type        = any
  default     = []
}
