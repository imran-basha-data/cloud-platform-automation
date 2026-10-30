resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_189:Public endpoint kept but firewalled (default Deny, AKS subnet service endpoint + operator IPs); a private endpoint needs private DNS and self-hosted CI runners.
  #checkov:skip=CKV2_AZURE_32:Same trade-off as CKV_AZURE_189: firewall plus subnet service endpoint instead of a private endpoint.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Azure RBAC instead of legacy access policies.
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = var.allowed_ip_ranges
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = var.tags
}
