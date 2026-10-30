variable "name" {
  description = "Key Vault name: globally unique, 3-24 alphanumeric characters or hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault names must be 3-24 characters, start with a letter and end alphanumeric."
  }
}

variable "resource_group_name" {
  description = "Resource group for the vault."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant that owns the vault."
  type        = string
}

variable "allowed_subnet_ids" {
  description = "Subnets (with a Microsoft.KeyVault service endpoint) allowed through the firewall."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Operator CIDRs allowed through the vault firewall (needed to manage secrets)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
