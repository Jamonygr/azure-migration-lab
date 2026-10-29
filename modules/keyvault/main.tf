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
variable "tags" {
  type = map(string)
}
resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_110:Purge protection would block deterministic teardown of this disposable lab vault; seven-day soft delete and private RBAC access remain enabled.
  #checkov:skip=CKV_AZURE_42:Teardown deliberately purges this synthetic-data lab vault; seven-day soft delete is configured while the lab runs.
  #checkov:skip=CKV2_AZURE_32:The foundation creates the vault private endpoint through azurerm_private_endpoint.service["vault"] and links private DNS to both VNets; the cross-module for_each graph is not resolved by this check.
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  tags                          = var.tags
  network_acls {
    default_action = "Deny"
    bypass         = "None"
  }
}
output "id" { value = azurerm_key_vault.this.id }
output "name" { value = azurerm_key_vault.this.name }
variable "enable_monitoring" {
  type    = bool
  default = false
}
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
resource "azurerm_monitor_diagnostic_setting" "audit" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "migration-vault-audit"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enabled_log { category = "AuditEvent" }
}
