resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_115:API server is restricted with authorized IP ranges instead; a private cluster needs private DNS and self-hosted CI runners.
  #checkov:skip=CKV_AZURE_117:Platform-managed keys plus encryption at host; customer-managed keys need a Disk Encryption Set and key rotation process.
  #checkov:skip=CKV_AZURE_170:Free tier is intentional for dev; prod is forced to Standard by a plan-time precondition.
  #checkov:skip=CKV_AZURE_226:Ephemeral OS disks depend on the VM size's cache/temp disk; the default sizes have none.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # Patch upgrades and node image updates are applied automatically.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Entra ID + Azure RBAC only: no static admin kubeconfig.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  oidc_issuer_enabled          = true
  workload_identity_enabled    = true
  azure_policy_enabled         = true
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_node_vm_size
    vnet_subnet_id              = var.subnet_id
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    zones                       = var.availability_zones
    os_sku                      = "AzureLinux"
    max_pods                    = 50
    host_encryption_enabled     = var.host_encryption_enabled
    temporary_name_for_rotation = "systemtmp"
    # System pool runs cluster add-ons only; workloads go to the "apps" pool.
    only_critical_addons_enabled = true

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # Pre-created identities: role assignments exist before the cluster does,
  # so there is no race between cluster creation and its permissions.
  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity_id]
  }

  kubelet_identity {
    client_id                 = var.kubelet_identity.client_id
    object_id                 = var.kubelet_identity.object_id
    user_assigned_identity_id = var.kubelet_identity.id
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.authorized_ip_ranges
    }
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = var.tags

  lifecycle {
    # The autoscaler owns the node count.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

# User node pool for application workloads, separate from system add-ons.
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  #checkov:skip=CKV_AZURE_226:Ephemeral OS disks depend on the VM size's cache/temp disk; the default sizes have none.
  name                    = "apps"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.apps_node_vm_size
  vnet_subnet_id          = var.subnet_id
  auto_scaling_enabled    = true
  min_count               = var.node_min_count
  max_count               = var.node_max_count
  zones                   = var.availability_zones
  os_sku                  = "AzureLinux"
  max_pods                = 50
  host_encryption_enabled = var.host_encryption_enabled
  tags                    = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
