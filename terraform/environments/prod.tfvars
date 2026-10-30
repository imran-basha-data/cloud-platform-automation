environment         = "prod"
location            = "uksouth"
aks_sku_tier        = "Standard"
system_node_vm_size = "Standard_D2s_v5"
apps_node_vm_size   = "Standard_D4s_v5"
node_min_count      = 3
node_max_count      = 6
availability_zones  = ["1", "2", "3"]
acr_sku             = "Premium"
log_retention_days  = 90
log_daily_quota_gb  = 10
# Replace with your organisation's egress ranges (documentation range shown).
authorized_ip_ranges = ["203.0.113.0/24"]
