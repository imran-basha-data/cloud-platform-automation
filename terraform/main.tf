locals {
  name_prefix = "${var.project}-${var.environment}"
  # Globally unique names (ACR, Key Vault) cannot contain hyphens.
  compact_name = "${var.project}${var.environment}${substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 6)}"

  tags = merge(
    {
      project     = var.project
      environment = var.environment
      managed_by  = "terraform"
      repository  = "imran-basha-data/cloud-platform-automation"
    },
    var.tags,
  )
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags

  lifecycle {
    # Production guardrails, enforced at plan time.
    precondition {
      condition     = var.environment != "prod" || length(var.authorized_ip_ranges) > 0
      error_message = "prod requires authorized_ip_ranges so the AKS API server and Key Vault are not public."
    }
    precondition {
      condition     = var.environment != "prod" || var.aks_sku_tier == "Standard"
      error_message = "prod requires aks_sku_tier = \"Standard\" for the uptime SLA."
    }
    precondition {
      condition     = var.node_min_count <= var.node_max_count
      error_message = "node_min_count must not exceed node_max_count."
    }
  }
}

module "network" {
  source = "./modules/network"

  name                = "vnet-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.vnet_address_space
  aks_subnet_prefix   = var.aks_subnet_prefix
  tags                = local.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  name                = "log-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  retention_days      = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

module "container_registry" {
  source = "./modules/container_registry"

  name                = "acr${local.compact_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.acr_sku
  tags                = local.tags
}

module "key_vault" {
  source = "./modules/key_vault"

  name                = "kv${local.compact_name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  allowed_ip_ranges   = var.authorized_ip_ranges
  allowed_subnet_ids  = [module.network.aks_subnet_id]
  tags                = local.tags
}

module "aks" {
  source = "./modules/aks"

  name                       = "aks-${local.name_prefix}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  kubernetes_version         = var.kubernetes_version
  sku_tier                   = var.aks_sku_tier
  subnet_id                  = module.network.aks_subnet_id
  system_node_vm_size        = var.system_node_vm_size
  apps_node_vm_size          = var.apps_node_vm_size
  host_encryption_enabled    = var.host_encryption_enabled
  node_min_count             = var.node_min_count
  node_max_count             = var.node_max_count
  availability_zones         = var.availability_zones
  authorized_ip_ranges       = var.authorized_ip_ranges
  log_analytics_workspace_id = module.monitoring.workspace_id
  tags                       = local.tags
}

# Nodes pull images from ACR with their managed identity; no registry passwords.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = module.container_registry.id
  role_definition_name             = "AcrPull"
  principal_id                     = module.aks.kubelet_object_id
  skip_service_principal_aad_check = true
}

# The Key Vault CSI driver add-on reads secrets with its own identity.
resource "azurerm_role_assignment" "aks_key_vault_secrets" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.aks.key_vault_secrets_provider_object_id
}
