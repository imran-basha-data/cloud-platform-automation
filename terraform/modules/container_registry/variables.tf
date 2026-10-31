variable "name" {
  description = "Registry name: globally unique, 5-50 alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "ACR names must be 5-50 alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "Resource group for the registry."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku" {
  description = "Basic, Standard or Premium."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
