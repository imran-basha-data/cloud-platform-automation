output "id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}
