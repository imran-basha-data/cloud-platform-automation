provider "azurerm" {
  # Null falls back to ARM_SUBSCRIPTION_ID, so no subscription ID is committed.
  subscription_id = var.subscription_id

  features {
    key_vault {
      # Never purge soft-deleted vaults automatically on destroy.
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
