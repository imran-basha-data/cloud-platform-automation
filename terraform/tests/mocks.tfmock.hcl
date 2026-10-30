# Shared mock data so plans can resolve computed identity attributes without Azure.
mock_data "azurerm_client_config" {
  defaults = {
    tenant_id       = "00000000-0000-0000-0000-000000000001"
    subscription_id = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
    client_id       = "00000000-0000-0000-0000-000000000004"
  }
}

mock_resource "azurerm_kubernetes_cluster" {
  defaults = {
    id              = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks"
    oidc_issuer_url = "https://uksouth.oic.prod-aks.azure.com/tenant/issuer/"
  }
}

mock_resource "azurerm_user_assigned_identity" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id"
    client_id    = "00000000-0000-0000-0000-000000000011"
    principal_id = "00000000-0000-0000-0000-000000000012"
    tenant_id    = "00000000-0000-0000-0000-000000000001"
  }
}

mock_resource "azurerm_container_registry" {
  defaults = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/acr"
    login_server = "acrplatformdev.azurecr.io"
  }
}

mock_resource "azurerm_key_vault" {
  defaults = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
    vault_uri = "https://kvplatformdev.vault.azure.net/"
  }
}

mock_resource "azurerm_subnet" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-aks"
  }
}

mock_resource "azurerm_log_analytics_workspace" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/log"
  }
}

# Every resource whose ID is passed to another resource needs a well-formed
# Azure ID: the provider still parses IDs when planning the mock teardown.
mock_resource "azurerm_resource_group" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev"
  }
}

mock_resource "azurerm_virtual_network" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev/providers/Microsoft.Network/virtualNetworks/vnet"
  }
}

mock_resource "azurerm_network_security_group" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev/providers/Microsoft.Network/networkSecurityGroups/nsg"
  }
}

mock_resource "azurerm_subnet_network_security_group_association" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-aks"
  }
}

mock_resource "azurerm_kubernetes_cluster_node_pool" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev/providers/Microsoft.ContainerService/managedClusters/aks/agentPools/apps"
  }
}

mock_resource "azurerm_role_assignment" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000099"
  }
}

mock_resource "azurerm_federated_identity_credential" {
  defaults = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-platform-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id/federatedIdentityCredentials/platform-api"
  }
}
