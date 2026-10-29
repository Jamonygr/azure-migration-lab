module "sql" {
  source                     = "../../modules/sql"
  name                       = "sql-${local.name}-${var.foundation_manifest.suffix}"
  resource_group_name        = var.foundation_manifest.target_rg
  location                   = var.location
  tenant_id                  = var.foundation_manifest.tenant_id
  migration_principal_id     = var.foundation_manifest.migration_identity_principal_id
  tags                       = local.tags
  enable_monitoring          = var.enable_monitoring
  log_analytics_workspace_id = try(var.foundation_manifest.log_analytics_workspace_id, null)
}
resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${local.name}-sql"
  location            = var.location
  resource_group_name = var.foundation_manifest.target_rg
  subnet_id           = var.foundation_manifest.private_endpoint_subnet_id
  tags                = local.tags
  private_service_connection {
    name                           = "connection-sql"
    private_connection_resource_id = module.sql.server_id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.foundation_manifest.private_dns_zone_ids.sql]
  }
}
resource "azurerm_role_assignment" "runtime_blob" {
  scope                = "${var.foundation_manifest.storage_account_id}/blobServices/default/containers/${var.foundation_manifest.staging_container_name}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.vm.manifest.identity_principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_role_assignment" "runtime_files" {
  scope                = "${var.foundation_manifest.storage_account_id}/fileServices/default/fileshares/${var.foundation_manifest.file_share_name}"
  role_definition_name = "Storage File Data Privileged Reader"
  principal_id         = module.vm.manifest.identity_principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_role_assignment" "runtime_secrets" {
  scope                = var.foundation_manifest.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.vm.manifest.identity_principal_id
  principal_type       = "ServicePrincipal"
}
output "manifest" {
  description = "Target runtime and database contract; no credentials are exposed."
  value = merge(module.vm.manifest, {
    application_url = "http://${module.vm.manifest.private_ip}"
    sql_server_name = module.sql.server_name
    sql_server_id   = module.sql.server_id
    sql_fqdn        = module.sql.fqdn
    database_name   = module.sql.database_name
    database_id     = module.sql.database_id
  })
}
