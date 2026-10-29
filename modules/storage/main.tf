variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "tags" {
  type = map(string)
}
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_33:Queue storage is unused and shared-key access is disabled; migration uses only blobs and files with Azure Monitor diagnostics.
  #checkov:skip=CKV_AZURE_206:LRS is intentional for disposable synthetic migration data; cross-region resilience is outside this lab.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption keys are retained for this disposable lab; customer-managed key lifecycle is a separate production exercise.
  #checkov:skip=CKV2_AZURE_33:Foundation creates distinct blob/file private endpoints through azurerm_private_endpoint.service and private DNS links to both VNets; cross-module for_each causes the graph check to miss these edges.
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  tags                            = var.tags
  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 7 }
    container_delete_retention_policy { days = 7 }
  }
  network_rules { default_action = "Deny" }
}
# Resource Manager IDs keep provisioning independent of private data-plane access.
resource "azurerm_storage_container" "artifacts" {
  #checkov:skip=CKV2_AZURE_21:azurerm_monitor_diagnostic_setting.services["blob"] explicitly enables StorageRead, StorageWrite and StorageDelete into Log Analytics. The scanner cannot resolve the for_each service suffix on the diagnostic target ID.
  name                  = "artifacts"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
resource "azurerm_storage_share" "migration" {
  name               = "migration"
  storage_account_id = azurerm_storage_account.this.id
  quota              = 5
  enabled_protocol   = "SMB"
}
output "id" { value = azurerm_storage_account.this.id }
output "name" { value = azurerm_storage_account.this.name }
output "staging_container_name" { value = azurerm_storage_container.artifacts.name }
output "file_share_name" { value = azurerm_storage_share.migration.name }
variable "enable_monitoring" {
  type    = bool
  default = false
}
variable "log_analytics_workspace_id" {
  type    = string
  default = null
}
resource "azurerm_monitor_diagnostic_setting" "services" {
  for_each                   = var.enable_monitoring ? toset(["blob", "file"]) : toset([])
  name                       = "migration-${each.key}-audit"
  target_resource_id         = "${azurerm_storage_account.this.id}/${each.key}Services/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enabled_log { category = "StorageRead" }
  enabled_log { category = "StorageWrite" }
  enabled_log { category = "StorageDelete" }
}
