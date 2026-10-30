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
    kubelet_identity = [{
      client_id                 = "00000000-0000-0000-0000-000000000011"
      object_id                 = "00000000-0000-0000-0000-000000000012"
      user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/kubelet"
    }]
    key_vault_secrets_provider = [{
      secret_rotation_enabled  = true
      secret_rotation_interval = "2m"
      secret_identity = [{
        client_id                 = "00000000-0000-0000-0000-000000000021"
        object_id                 = "00000000-0000-0000-0000-000000000022"
        user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/kv"
      }]
    }]
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
