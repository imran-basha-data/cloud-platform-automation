output "vnet_id" {
  description = "Virtual network ID."
  value       = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  description = "Subnet ID for the AKS node pool."
  value       = azurerm_subnet.aks.id
}
