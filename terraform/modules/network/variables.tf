variable "name" {
  description = "Virtual network name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the network."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "address_space" {
  description = "VNet CIDR."
  type        = string
}

variable "aks_subnet_prefix" {
  description = "AKS subnet CIDR; must sit inside address_space."
  type        = string

  validation {
    condition     = tonumber(split("/", var.aks_subnet_prefix)[1]) <= 24
    error_message = "aks_subnet_prefix must be /24 or larger: Azure CNI assigns pod IPs from it."
  }
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
