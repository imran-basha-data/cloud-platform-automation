terraform {
  # 1.7+ is needed for mock providers in `terraform test`.
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Remote state in an Azure Storage account, one state file per environment.
  # Supplied at init time:  terraform init -backend-config=environments/<env>.backend.hcl
  backend "azurerm" {}
}
