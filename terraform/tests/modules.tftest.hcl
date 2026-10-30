# Module-level plan tests: each module's security-relevant settings.

mock_provider "azurerm" {
  source = "./tests"
}

run "aks_is_locked_down" {
  command = plan

  module {
    source = "./modules/aks"
  }

  variables {
    name                       = "aks-platform-dev"
    resource_group_name        = "rg-platform-dev"
    location                   = "uksouth"
    tenant_id                  = "00000000-0000-0000-0000-000000000001"
    sku_tier                   = "Free"
    subnet_id                  = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/v/subnets/s"
    system_node_vm_size        = "Standard_D2s_v5"
    apps_node_vm_size          = "Standard_D2s_v5"
    node_min_count             = 1
    node_max_count             = 3
    authorized_ip_ranges       = ["203.0.113.0/24"]
    log_analytics_workspace_id = "/subscriptions/x/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/log"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled
    error_message = "static admin credentials must be disabled"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled
    error_message = "Azure RBAC for Kubernetes must be enabled"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled && azurerm_kubernetes_cluster.this.workload_identity_enabled
    error_message = "workload identity must be enabled"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "azure"
    error_message = "a network policy engine is required for NetworkPolicy objects"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled
    error_message = "cluster autoscaler must be enabled"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.api_server_access_profile[0].authorized_ip_ranges == toset(["203.0.113.0/24"])
    error_message = "API server must be restricted to the authorised ranges"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.automatic_upgrade_channel == "patch"
    error_message = "automatic patch upgrades must be on"
  }
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled
    error_message = "system pool must be reserved for critical add-ons"
  }
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.apps.mode == "User" && azurerm_kubernetes_cluster_node_pool.apps.host_encryption_enabled
    error_message = "workloads must run on an encrypted user node pool"
  }
}

run "acr_basic_has_no_admin_user" {
  command = plan

  module {
    source = "./modules/container_registry"
  }

  variables {
    name                = "acrplatformdev123"
    resource_group_name = "rg"
    location            = "uksouth"
    sku                 = "Basic"
  }

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false && azurerm_container_registry.this.anonymous_pull_enabled == false
    error_message = "registry must not allow admin or anonymous access"
  }
}

run "acr_premium_is_private_and_zone_redundant" {
  command = plan

  module {
    source = "./modules/container_registry"
  }

  variables {
    name                = "acrplatformprod123"
    resource_group_name = "rg"
    location            = "uksouth"
    sku                 = "Premium"
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == false
    error_message = "Premium registry must disable public network access"
  }
  assert {
    condition     = azurerm_container_registry.this.zone_redundancy_enabled
    error_message = "Premium registry must be zone redundant"
  }
}

run "acr_name_with_hyphen_is_rejected" {
  command = plan

  module {
    source = "./modules/container_registry"
  }

  variables {
    name                = "acr-platform"
    resource_group_name = "rg"
    location            = "uksouth"
    sku                 = "Basic"
  }

  expect_failures = [var.name]
}

run "key_vault_uses_rbac_purge_protection_and_firewall" {
  command = plan

  module {
    source = "./modules/key_vault"
  }

  variables {
    name                = "kvplatformdev123"
    resource_group_name = "rg"
    location            = "uksouth"
    tenant_id           = "00000000-0000-0000-0000-000000000001"
    allowed_ip_ranges   = []
    allowed_subnet_ids  = ["/subscriptions/x/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/v/subnets/aks"]
  }

  assert {
    condition     = azurerm_key_vault.this.enable_rbac_authorization && azurerm_key_vault.this.purge_protection_enabled
    error_message = "Key Vault must use RBAC and purge protection"
  }
  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "Key Vault firewall must deny by default even with no operator ranges"
  }
}

run "aks_subnet_too_small_is_rejected" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    name                = "vnet"
    resource_group_name = "rg"
    location            = "uksouth"
    address_space       = "10.20.0.0/16"
    aks_subnet_prefix   = "10.20.0.0/27"
  }

  expect_failures = [var.aks_subnet_prefix]
}
