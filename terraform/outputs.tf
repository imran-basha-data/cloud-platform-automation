output "resource_group_name" {
  description = "Resource group holding every resource for this environment."
  value       = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  description = "AKS cluster name, for `az aks get-credentials`."
  value       = module.aks.name
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer for workload identity federation."
  value       = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  description = "Registry host used as the image prefix in k8s/overlays/prod."
  value       = module.container_registry.login_server
}

output "key_vault_uri" {
  description = "Key Vault URI for application secrets (e.g. the admin token)."
  value       = module.key_vault.uri
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving AKS Container Insights data."
  value       = module.monitoring.workspace_id
}
