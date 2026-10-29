mock_provider "azurerm" {}
mock_provider "random" {}
run "sql_uses_stable_migration_admin" {
  command = plan
  module { source = "../../modules/sql" }
  variables {
    name                   = "sql-test"
    resource_group_name    = "rg-target"
    location               = "westeurope"
    tenant_id              = "22222222-2222-4222-8222-222222222222"
    migration_principal_id = "33333333-3333-4333-8333-333333333333"
    tags                   = {}
  }
  assert {
    condition     = azurerm_mssql_server.this.azuread_administrator[0].object_id == var.migration_principal_id && azurerm_mssql_server.this.connection_policy == "Proxy"
    error_message = "Migration identity must administer SQL through the explicitly allowed private 1433 path."
  }
}
