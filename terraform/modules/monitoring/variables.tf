variable "name" {
  description = "Log Analytics workspace name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the workspace."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "retention_days" {
  description = "Data retention in days."
  type        = number
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 for unlimited)."
  type        = number
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
