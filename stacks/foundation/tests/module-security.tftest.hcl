mock_provider "azurerm" {}
mock_provider "random" {}
run "storage_private_oauth_only" {
  command = plan
  module { source = "../../modules/storage" }
  variables {
    name                = "stmigrationtest"
    resource_group_name = "rg-test"
    location            = "westeurope"
    tags                = {}
  }
  assert {
    condition     = !azurerm_storage_account.this.public_network_access_enabled && !azurerm_storage_account.this.shared_access_key_enabled && !azurerm_storage_account.this.allow_nested_items_to_be_public
    error_message = "Storage must require private access and identity-based authentication."
  }
  assert {
    condition     = azurerm_storage_share.migration.name == "migration" && azurerm_storage_container.artifacts.container_access_type == "private"
    error_message = "File share must exist before AzCopy and artifacts must stay private."
  }
}
run "sql_empty_and_entra_only" {
  command = plan
  module { source = "../../modules/sql" }
  variables {
    name                   = "sql-migration-test"
    resource_group_name    = "rg-test"
    location               = "westeurope"
    tenant_id              = "22222222-2222-4222-8222-222222222222"
    migration_principal_id = "33333333-3333-4333-8333-333333333333"
    tags                   = {}
  }
  assert {
    condition     = azurerm_mssql_server.this.azuread_administrator[0].azuread_authentication_only && !azurerm_mssql_server.this.public_network_access_enabled && azurerm_mssql_database.this.name == "MigrationCatalog"
    error_message = "SQL must expose only the private Entra-authenticated empty migration database."
  }
}
run "network_rejects_overlapping_cidrs" {
  command = plan
  module { source = "../../modules/networking" }
  variables {
    name                 = "test"
    location             = "westeurope"
    source_rg            = "rg-source"
    target_rg            = "rg-target"
    source_address_space = "10.100.0.0/16"
    target_address_space = "10.100.0.0/17"
    enable_nat           = false
    enable_public_rdp    = false
    allowed_rdp_cidrs    = []
    tags                 = {}
  }
  expect_failures = [azurerm_virtual_network.site]
}
run "network_rejects_unlisted_rdp" {
  command = plan
  module { source = "../../modules/networking" }
  variables {
    name                 = "test"
    location             = "westeurope"
    source_rg            = "rg-source"
    target_rg            = "rg-target"
    source_address_space = "10.100.0.0/16"
    target_address_space = "10.200.0.0/16"
    enable_nat           = false
    enable_public_rdp    = true
    allowed_rdp_cidrs    = []
    tags                 = {}
  }
  expect_failures = [azurerm_virtual_network.site]
}
run "budget_uses_first_apply_month" {
  command = plan
  module { source = "../../modules/budget" }
  variables {
    resource_groups = { source = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-source" }
    amount          = 25
    emails          = ["lab-owner@example.com"]
    start_date      = null
  }
  assert {
    condition     = length(azurerm_consumption_budget_resource_group.this) == 1 && azurerm_consumption_budget_resource_group.this["source"].time_period[0].start_date == formatdate("YYYY-MM-01'T'00:00:00'Z'", plantimestamp())
    error_message = "Budgets need a real recipient and the current first-apply month, not a stale hard-coded date."
  }
}
run "budgets_disabled_without_recipient" {
  command = plan
  module { source = "../../modules/budget" }
  variables {
    resource_groups = { source = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-source" }
    amount          = 25
    emails          = []
    start_date      = null
  }
  assert {
    condition     = length(azurerm_consumption_budget_resource_group.this) == 0
    error_message = "The example profile must not create budgets with fake notification destinations."
  }
}
