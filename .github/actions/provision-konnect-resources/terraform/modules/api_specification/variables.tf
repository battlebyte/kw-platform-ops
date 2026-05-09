variable "api_id" {
  description = "The API ID this specification belongs to"
  type        = string
}

variable "content" {
  description = "The raw content of the API specification (JSON or YAML). Requires replacement if changed"
  type        = string
}

variable "type" {
  description = "The specification type (e.g. 'oas3', 'asyncapi'). Defaults to provider behaviour when null"
  type        = string
  default     = null
}
