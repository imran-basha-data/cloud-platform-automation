environment         = "dev"
location            = "uksouth"
aks_sku_tier        = "Free"
system_node_vm_size = "Standard_B2s_v2"
apps_node_vm_size   = "Standard_B2s_v2"
node_min_count      = 1
node_max_count      = 2
availability_zones  = []
acr_sku             = "Basic"
log_retention_days  = 30
log_daily_quota_gb  = 1
# Dev leaves the API server reachable; set your own IP to restrict it.
authorized_ip_ranges = []
