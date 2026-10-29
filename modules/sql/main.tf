variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "tenant_id" {
  type = string
}
variable "migration_principal_id" {
  type = string
}
variable "tags" {
  type = map(string)
}
variable "enable_monitoring" {
  description = "Forward SQL audit events to the supplied Log Analytics workspace."
  type        = bool
  default     = false
}
variable "log_analytics_workspace_id" {
  description = "Workspace for SQL audit events; required when enable_monitoring is true."
  type        = string
  default     = null
}
resource "azurerm_mssql_server" "this" {
  #checkov:skip=CKV_AZURE_24:SQL audit events use the 30-day lab Log Analytics workspace. Storage-endpoint 90-day retention is not applicable to this low-cost Azure Monitor destination.
  #checkov:skip=CKV2_AZURE_2:Defender SQL vulnerability assessment is an optional paid production extension; this disposable synthetic-data lab uses private Entra-only SQL, audit logs and local security checks.
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  connection_policy             = "Proxy"
  azuread_administrator {
    login_username              = "migration-identity"
    object_id                   = var.migration_principal_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }
  tags = var.tags
}
# Scripts import schema/data AFTER Terraform creates an empty database.
resource "azurerm_mssql_database" "this" {
  #checkov:skip=CKV_AZURE_224:Ledger is not required for the ordinary catalog being migrated; enabling it would change the source schema and exercise semantics.
  #checkov:skip=CKV_AZURE_229:Basic 2GB is deliberately a disposable low-cost single-region target; zonal resilience is outside the migration exercise.
  name                                = "MigrationCatalog"
  server_id                           = azurerm_mssql_server.this.id
  sku_name                            = "Basic"
  max_size_gb                         = 2
  zone_redundant                      = false
  storage_account_type                = "Local"
  transparent_data_encryption_enabled = true
  tags                                = var.tags
  short_term_retention_policy { retention_days = 7 }
}
output "server_id" { value = azurerm_mssql_server.this.id }
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  enabled                = true
  log_monitoring_enabled = true
  audit_actions_and_groups = [
    "SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP",
    "FAILED_DATABASE_AUTHENTICATION_GROUP",
    "BATCH_COMPLETED_GROUP"
  ]
}
resource "azurerm_monitor_diagnostic_setting" "sql_audit" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "migration-sql-audit"
  target_resource_id         = "${azurerm_mssql_server.this.id}/databases/master"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enabled_log { category = "SQLSecurityAuditEvents" }
}
output "server_name" { value = azurerm_mssql_server.this.name }
output "fqdn" { value = azurerm_mssql_server.this.fully_qualified_domain_name }
output "database_name" { value = azurerm_mssql_database.this.name }
output "database_id" { value = azurerm_mssql_database.this.id }
