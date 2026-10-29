data "azurerm_client_config" "current" {}
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
resource "azurerm_resource_group" "lab" {
  for_each = toset(["source", "target", "shared", "assessment"])
  name     = "rg-${local.name}-${each.key}"
  location = var.location
  tags     = merge(local.tags, { MigrationRole = each.key })
}
module "networking" {
  source               = "../../modules/networking"
  name                 = local.name
  location             = var.location
  source_rg            = azurerm_resource_group.lab["source"].name
  target_rg            = azurerm_resource_group.lab["target"].name
  source_address_space = var.source_address_space
  target_address_space = var.target_address_space
  enable_nat           = var.enable_nat
  enable_public_rdp    = var.enable_public_rdp
  allowed_rdp_cidrs    = var.allowed_rdp_cidrs
  tags                 = local.tags
}
module "identity" {
  source              = "../../modules/identity"
  name                = "id-${local.name}-migration"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab["shared"].name
  tags                = local.tags
}
module "storage" {
  source                     = "../../modules/storage"
  name                       = "st${var.project}${replace(var.environment, "-", "")}${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.lab["shared"].name
  tags                       = local.tags
  enable_monitoring          = var.enable_monitoring
  log_analytics_workspace_id = try(module.monitoring[0].workspace_id, null)
}
module "keyvault" {
  source                     = "../../modules/keyvault"
  name                       = "kv${var.project}${replace(var.environment, "-", "")}${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.lab["shared"].name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  tags                       = local.tags
  enable_monitoring          = var.enable_monitoring
  log_analytics_workspace_id = try(module.monitoring[0].workspace_id, null)
}
locals {
  dns_zones = {
    blob        = "privatelink.blob.core.windows.net"
    file        = "privatelink.file.core.windows.net"
    vault       = "privatelink.vaultcore.azure.net"
    sql         = "privatelink.database.windows.net"
    application = "migration.lab.internal"
  }
  dns_links = { for pair in setproduct(keys(local.dns_zones), ["source", "target"]) : "${pair[0]}-${pair[1]}" => { zone = pair[0], site = pair[1] } }
  private_services = {
    blob  = { id = module.storage.id, subresource = "blob" }
    file  = { id = module.storage.id, subresource = "file" }
    vault = { id = module.keyvault.id, subresource = "vault" }
  }
}
resource "azurerm_private_dns_zone" "service" {
  for_each            = local.dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.lab["shared"].name
  tags                = local.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "service" {
  for_each              = local.dns_links
  name                  = "link-${each.value.site}"
  resource_group_name   = azurerm_resource_group.lab["shared"].name
  private_dns_zone_name = azurerm_private_dns_zone.service[each.value.zone].name
  virtual_network_id    = module.networking.vnets[each.value.site]
  registration_enabled  = false
  tags                  = local.tags
}
resource "azurerm_private_endpoint" "service" {
  for_each            = local.private_services
  name                = "pe-${local.name}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab["shared"].name
  subnet_id           = module.networking.private_endpoint_subnet_id
  tags                = local.tags
  private_service_connection {
    name                           = "connection-${each.key}"
    private_connection_resource_id = each.value.id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.service[each.key].id]
  }
}
resource "azurerm_role_assignment" "migration_blob" {
  scope                = "${module.storage.id}/blobServices/default/containers/${module.storage.staging_container_name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.identity.principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_role_assignment" "migration_file" {
  scope                = "${module.storage.id}/fileServices/default/fileshares/${module.storage.file_share_name}"
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = module.identity.principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_role_assignment" "migration_secrets" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = module.identity.principal_id
  principal_type       = "ServicePrincipal"
}
module "monitoring" {
  count               = var.enable_monitoring ? 1 : 0
  source              = "../../modules/monitoring"
  name                = local.name
  resource_group_name = azurerm_resource_group.lab["shared"].name
  location            = var.location
  enable_workbooks    = var.enable_workbooks
  tags                = local.tags
}
resource "azurerm_recovery_services_vault" "backup" {
  count               = var.enable_backup ? 1 : 0
  name                = "rsv-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab["shared"].name
  sku                 = "Standard"
  storage_mode_type   = "LocallyRedundant"
  soft_delete_enabled = false
  identity { type = "SystemAssigned" }
  tags = local.tags
}
resource "azurerm_backup_policy_vm" "daily" {
  count               = var.enable_backup ? 1 : 0
  name                = "daily-seven-days"
  resource_group_name = azurerm_resource_group.lab["shared"].name
  recovery_vault_name = azurerm_recovery_services_vault.backup[0].name
  timezone            = "UTC"
  backup {
    frequency = "Daily"
    time      = "18:00"
  }
  retention_daily { count = 7 }
}
module "budget" {
  source          = "../../modules/budget"
  resource_groups = { for key, rg in azurerm_resource_group.lab : key => rg.id }
  amount          = var.budget_amount
  emails          = var.budget_emails
  start_date      = var.budget_start_date
}
resource "azurerm_policy_definition" "owner" {
  count        = var.enable_policy ? 1 : 0
  name         = "${local.name}-audit-owner"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Migration lab resources should have an Owner tag"
  policy_rule  = jsonencode({ if = { field = "tags['Owner']", exists = "false" }, then = { effect = "audit" } })
}
resource "azurerm_resource_group_policy_assignment" "owner" {
  for_each             = var.enable_policy ? azurerm_resource_group.lab : {}
  name                 = "audit-owner"
  resource_group_id    = each.value.id
  policy_definition_id = azurerm_policy_definition.owner[0].id
  display_name         = "Audit missing migration resource owner"
}
output "manifest" {
  description = "Nonsensitive contract for source, target, cutover, and migration tooling."
  value = {
    subscription_id                 = var.subscription_id
    tenant_id                       = data.azurerm_client_config.current.tenant_id
    environment                     = var.environment
    location                        = var.location
    name                            = local.name
    suffix                          = random_string.suffix.result
    source_rg                       = azurerm_resource_group.lab["source"].name
    target_rg                       = azurerm_resource_group.lab["target"].name
    shared_rg                       = azurerm_resource_group.lab["shared"].name
    assessment_rg                   = azurerm_resource_group.lab["assessment"].name
    resource_group_names            = [for rg in azurerm_resource_group.lab : rg.name]
    source_subnet_id                = module.networking.subnets["source"]
    target_subnet_id                = module.networking.subnets["target"]
    source_private_ip               = module.networking.compute_addresses["source"]
    target_private_ip               = module.networking.compute_addresses["target"]
    private_endpoint_subnet_id      = module.networking.private_endpoint_subnet_id
    private_dns_zone_name           = azurerm_private_dns_zone.service["application"].name
    private_dns_rg                  = azurerm_resource_group.lab["shared"].name
    private_dns_zone_ids            = { for key, zone in azurerm_private_dns_zone.service : key => zone.id }
    storage_account_name            = module.storage.name
    storage_account_id              = module.storage.id
    staging_container_name          = module.storage.staging_container_name
    file_share_name                 = module.storage.file_share_name
    key_vault_name                  = module.keyvault.name
    key_vault_id                    = module.keyvault.id
    migration_identity_id           = module.identity.id
    migration_identity_client_id    = module.identity.client_id
    migration_identity_principal_id = module.identity.principal_id
    log_analytics_workspace_id      = try(module.monitoring[0].workspace_id, null)
    data_collection_rule_id         = try(module.monitoring[0].data_collection_rule_id, null)
    action_group_id                 = try(module.monitoring[0].action_group_id, null)
    backup_vault_name               = try(azurerm_recovery_services_vault.backup[0].name, null)
    backup_policy_id                = try(azurerm_backup_policy_vm.daily[0].id, null)
    source_egress_public_ip_id      = module.networking.nic_public_ip_ids["source"]
    target_egress_public_ip_id      = module.networking.nic_public_ip_ids["target"]
    enable_nat                      = var.enable_nat
  }
}
