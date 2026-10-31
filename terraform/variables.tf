variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "project" {
  description = "Short project name used in resource names (lowercase letters and digits)."
  type        = string
  default     = "platform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.project))
    error_message = "project must be 3-12 lowercase letters/digits and start with a letter."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "uksouth"

  validation {
    condition     = contains(["uksouth", "ukwest", "northeurope", "westeurope"], var.location)
    error_message = "location must be one of uksouth, ukwest, northeurope, westeurope."
  }
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block."
  }
}

variable "aks_subnet_prefix" {
  description = "Subnet for AKS nodes and pods (Azure CNI)."
  type        = string
  default     = "10.20.0.0/20"

  validation {
    condition     = can(cidrhost(var.aks_subnet_prefix, 0))
    error_message = "aks_subnet_prefix must be a valid CIDR block."
  }
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version (minor, e.g. 1.33). Null uses the AKS default."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "AKS control plane tier. Standard adds a financially backed uptime SLA."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.aks_sku_tier)
    error_message = "aks_sku_tier must be Free or Standard."
  }
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "apps_node_vm_size" {
  description = "VM size for the application node pool."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "host_encryption_enabled" {
  description = "Encryption at host for node disks. Register Microsoft.Compute/EncryptionAtHost on the subscription first."
  type        = bool
  default     = true
}

variable "node_min_count" {
  description = "Minimum nodes per pool for the cluster autoscaler."
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_count >= 1 && var.node_min_count <= 10
    error_message = "node_min_count must be between 1 and 10."
  }
}

variable "node_max_count" {
  description = "Maximum nodes per pool for the cluster autoscaler."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_count >= 1 && var.node_max_count <= 50
    error_message = "node_max_count must be between 1 and 50."
  }
}

variable "availability_zones" {
  description = "Availability zones for the node pool. Empty for regions without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "authorized_ip_ranges" {
  description = "CIDRs allowed to reach the AKS API server and Key Vault. Empty means unrestricted (dev only)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.authorized_ip_ranges : can(cidrhost(cidr, 0))])
    error_message = "Every entry in authorized_ip_ranges must be a valid CIDR block."
  }
}

variable "acr_sku" {
  description = "Container registry tier. Premium enables private access, zone redundancy and retention."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard or Premium."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap for Log Analytics in GB (-1 for no cap). Protects against runaway cost."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
