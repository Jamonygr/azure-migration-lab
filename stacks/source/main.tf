module "vm" {
  source                     = "../../modules/windows-vm"
  name                       = "vm-${local.name}-source"
  computer_name              = "mig-source"
  resource_group_name        = var.foundation_manifest.source_rg
  location                   = var.location
  size                       = var.source_vm_size
  subnet_id                  = var.foundation_manifest.source_subnet_id
  private_ip                 = var.foundation_manifest.source_private_ip
  public_ip_id               = var.foundation_manifest.source_egress_public_ip_id
  identity_ids               = [var.foundation_manifest.migration_identity_id]
  auto_shutdown_time         = var.auto_shutdown_time
  encryption_at_host_enabled = var.enable_vm_encryption_at_host
  tags                       = merge(local.tags, { MigrationRole = "source" })
}
resource "azurerm_virtual_machine_extension" "monitor" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = module.vm.manifest.vm_id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}
resource "azurerm_monitor_data_collection_rule_association" "vm" {
  count                   = var.enable_monitoring ? 1 : 0
  name                    = "migration-performance"
  target_resource_id      = module.vm.manifest.vm_id
  data_collection_rule_id = var.foundation_manifest.data_collection_rule_id
}
resource "azurerm_monitor_metric_alert" "cpu" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "alert-${local.name}-source-cpu"
  resource_group_name = var.foundation_manifest.source_rg
  scopes              = [module.vm.manifest.vm_id]
  description         = "Sustained high CPU may lengthen migration downtime."
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }
  action { action_group_id = var.foundation_manifest.action_group_id }
}
resource "azurerm_backup_protected_vm" "vm" {
  count               = var.enable_backup ? 1 : 0
  resource_group_name = var.foundation_manifest.shared_rg
  recovery_vault_name = var.foundation_manifest.backup_vault_name
  source_vm_id        = module.vm.manifest.vm_id
  backup_policy_id    = var.foundation_manifest.backup_policy_id
}
