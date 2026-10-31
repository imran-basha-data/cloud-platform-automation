variable "name" {
  description = "Cluster name (also used as the DNS prefix)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Entra ID tenant for Kubernetes RBAC."
  type        = string
}

variable "control_plane_identity_id" {
  description = "Resource ID of the user-assigned identity for the AKS control plane."
  type        = string
}

variable "kubelet_identity" {
  description = "User-assigned identity used by the nodes (kubelet) to pull images."
  type = object({
    id        = string
    client_id = string
    object_id = string
  })
}

variable "kubernetes_version" {
  description = "Kubernetes minor version, or null for the AKS default."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "Free or Standard."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for nodes and pods (Azure CNI)."
  type        = string
}

variable "system_node_vm_size" {
  description = "VM size for the system node pool (add-ons only)."
  type        = string
}

variable "apps_node_vm_size" {
  description = "VM size for the application (user) node pool."
  type        = string
}

variable "host_encryption_enabled" {
  description = "Encrypt temp disks, caches and data in transit to storage on the VM host. Requires the EncryptionAtHost feature on the subscription."
  type        = bool
  default     = true
}

variable "node_min_count" {
  description = "Autoscaler minimum."
  type        = number
}

variable "node_max_count" {
  description = "Autoscaler maximum."
  type        = number
}

variable "availability_zones" {
  description = "Zones for the node pool."
  type        = list(string)
  default     = []
}

variable "authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server. Empty leaves it public (dev only)."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Workspace for Container Insights."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
