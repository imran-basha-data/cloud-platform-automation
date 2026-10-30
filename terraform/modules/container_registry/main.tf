resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_233:Zone redundancy is enabled when sku is Premium (prod); Basic (dev) does not support it.
  #checkov:skip=CKV_AZURE_165:Single-region deployment; geo-replication adds cost without a second region to serve.
  #checkov:skip=CKV_AZURE_164:Docker Content Trust is deprecated in ACR; image signing should use Notation, outside this project's scope.
  #checkov:skip=CKV_AZURE_166:ACR quarantine is a preview feature; images are scanned in CI (Trivy) before they are pushed.
  #checkov:skip=CKV_AZURE_163:Registry vulnerability scanning is Microsoft Defender for Containers, a subscription-level paid plan, not a registry setting.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # Identity-based pulls only; no shared admin username/password.
  admin_enabled          = false
  anonymous_pull_enabled = false

  # Only Premium supports disabling public access, zone redundancy and retention.
  public_network_access_enabled = var.sku != "Premium"
  zone_redundancy_enabled       = var.sku == "Premium"
  retention_policy_in_days      = var.sku == "Premium" ? 30 : null
  data_endpoint_enabled         = var.sku == "Premium"

  tags = var.tags
}
