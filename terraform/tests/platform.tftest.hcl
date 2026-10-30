# Plan-only tests against a mocked azurerm provider: no Azure credentials,
# no resources created, no cost. They prove naming, wiring, secure defaults
# and that invalid or unsafe input is rejected at plan time.

mock_provider "azurerm" {
  source = "./tests"
}

variables {
  environment = "dev"
}

run "dev_plan_wires_modules_and_names_resources" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-platform-dev"
    error_message = "resource group should follow rg-<project>-<env>"
  }
  assert {
    condition     = azurerm_resource_group.this.tags["managed_by"] == "terraform" && azurerm_resource_group.this.tags["environment"] == "dev"
    error_message = "standard tags missing"
  }
  assert {
    condition     = azurerm_role_assignment.aks_acr_pull.role_definition_name == "AcrPull"
    error_message = "AKS kubelet identity must get AcrPull on the registry"
  }
  assert {
    condition     = azurerm_role_assignment.aks_acr_pull.principal_id == "00000000-0000-0000-0000-000000000012"
    error_message = "AcrPull must be granted to the kubelet identity"
  }
  assert {
    condition     = azurerm_role_assignment.aks_key_vault_secrets.role_definition_name == "Key Vault Secrets User"
    error_message = "the CSI driver identity must be able to read secrets"
  }
}

run "prod_plan_with_guardrails_satisfied" {
  command = plan

  variables {
    environment          = "prod"
    aks_sku_tier         = "Standard"
    acr_sku              = "Premium"
    node_min_count       = 3
    node_max_count       = 6
    authorized_ip_ranges = ["203.0.113.0/24"]
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-platform-prod"
    error_message = "prod resource group name is wrong"
  }
}

run "prod_without_authorized_ip_ranges_is_rejected" {
  command = plan

  variables {
    environment  = "prod"
    aks_sku_tier = "Standard"
  }

  expect_failures = [azurerm_resource_group.this]
}

run "prod_without_uptime_sla_is_rejected" {
  command = plan

  variables {
    environment          = "prod"
    aks_sku_tier         = "Free"
    authorized_ip_ranges = ["203.0.113.0/24"]
  }

  expect_failures = [azurerm_resource_group.this]
}

run "autoscaler_bounds_must_be_ordered" {
  command = plan

  variables {
    node_min_count = 4
    node_max_count = 2
  }

  expect_failures = [azurerm_resource_group.this]
}

run "unknown_environment_is_rejected" {
  command = plan

  variables {
    environment = "test"
  }

  expect_failures = [var.environment]
}

run "invalid_cidr_is_rejected" {
  command = plan

  variables {
    authorized_ip_ranges = ["not-a-cidr"]
  }

  expect_failures = [var.authorized_ip_ranges]
}

run "region_outside_allow_list_is_rejected" {
  command = plan

  variables {
    location = "eastus"
  }

  expect_failures = [var.location]
}
