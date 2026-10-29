mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "11111111-1111-4111-8111-111111111111"
      tenant_id       = "22222222-2222-4222-8222-222222222222"
      object_id       = "33333333-3333-4333-8333-333333333333"
    }
  }
}
mock_provider "random" {}
variables {
  subscription_id = "11111111-1111-4111-8111-111111111111"
  budget_emails   = []
}
run "cheap_lab_complete_private_foundation" {
  command = plan
  variables {
    environment       = "cheap-lab"
    enable_nat        = false
    enable_monitoring = true
    enable_workbooks  = false
    enable_backup     = false
    enable_policy     = false
  }
  assert {
    condition     = length(azurerm_resource_group.lab) == 4 && length(azurerm_private_endpoint.service) == 3 && length(azurerm_private_dns_zone_virtual_network_link.service) == 10
    error_message = "The smallest profile must retain all resource groups and private blob/file/vault connectivity with both VNet DNS links."
  }
  assert {
    condition     = length(module.monitoring) == 1 && length(azurerm_recovery_services_vault.backup) == 0 && length(azurerm_policy_definition.owner) == 0
    error_message = "Cheap lab must keep basic diagnostics without premium backup or policy resources."
  }
  assert {
    condition     = module.networking.compute_addresses.source == "10.100.1.4" && module.networking.compute_addresses.target == "10.200.1.4"
    error_message = "Default source and target addresses must match documentation and guest manifests."
  }
}
run "dev_isolated_profile" {
  command = plan
  variables { environment = "dev" }
  assert {
    condition     = azurerm_resource_group.lab["source"].name == "rg-azmig-dev-source"
    error_message = "Dev must use its own resource names."
  }
}
run "lab_backup_and_workbook" {
  command = plan
  variables {
    environment      = "lab"
    enable_backup    = true
    enable_workbooks = true
  }
  assert {
    condition     = length(azurerm_recovery_services_vault.backup) == 1 && length(azurerm_backup_policy_vm.daily) == 1
    error_message = "Lab profile must provide a real vault and daily backup policy."
  }
}
run "production_like_profile" {
  command = plan
  variables {
    environment      = "prod"
    enable_nat       = true
    enable_backup    = true
    enable_workbooks = true
    enable_policy    = true
  }
  assert {
    condition     = module.networking.nic_public_ip_ids.source == null && module.networking.nic_public_ip_ids.target == null && length(azurerm_resource_group_policy_assignment.owner) == 4
    error_message = "Production-like profile must use NAT and keep VMs private, with scoped policy assignments."
  }
}
run "unrestricted_rdp_rejected" {
  command = plan
  variables {
    enable_public_rdp = true
    allowed_rdp_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.allowed_rdp_cidrs]
}
