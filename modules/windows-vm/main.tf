variable "name" {
  type = string
}
variable "computer_name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "size" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "private_ip" {
  type = string
}
variable "public_ip_id" {
  type    = string
  default = null
}
variable "identity_ids" {
  type    = list(string)
  default = []
}
variable "auto_shutdown_time" {
  type    = string
  default = "2000"
}
variable "tags" {
  type = map(string)
}
variable "encryption_at_host_enabled" {
  description = "Enable only after confirming regional SKU capability and subscription registration; OS/data disks always use Azure encryption at rest."
  type        = bool
  default     = false
}
resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!@#%&*-_+="
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}
resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip
    public_ip_address_id          = var.public_ip_id
  }
}
resource "azurerm_windows_virtual_machine" "this" {
  #checkov:skip=CKV_AZURE_50:VM extensions are required by Azure Monitor and Run Command, the lab's default administration path. No public management ports are enabled by default.
  #checkov:skip=CKV_AZURE_151:Host encryption is an explicit opt-in requiring regional SKU and subscription support. Lab-sized B-series availability must not be silently upgraded; managed disks remain encrypted at rest.
  name                       = var.name
  computer_name              = var.computer_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  size                       = var.size
  admin_username             = "labadmin"
  admin_password             = random_password.admin.result
  network_interface_ids      = [azurerm_network_interface.this.id]
  provision_vm_agent         = true
  automatic_updates_enabled  = true
  patch_mode                 = "AutomaticByPlatform"
  patch_assessment_mode      = "AutomaticByPlatform"
  secure_boot_enabled        = true
  vtpm_enabled               = true
  encryption_at_host_enabled = var.encryption_at_host_enabled
  tags                       = var.tags
  identity {
    type         = length(var.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = var.identity_ids
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  boot_diagnostics {}
}
resource "azurerm_dev_test_global_vm_shutdown_schedule" "this" {
  virtual_machine_id    = azurerm_windows_virtual_machine.this.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = "UTC"
  notification_settings { enabled = false }
  tags = var.tags
}
output "manifest" {
  value = {
    vm_name               = azurerm_windows_virtual_machine.this.name
    vm_id                 = azurerm_windows_virtual_machine.this.id
    resource_group        = var.resource_group_name
    private_ip            = var.private_ip
    identity_principal_id = azurerm_windows_virtual_machine.this.identity[0].principal_id
    computer_name         = var.computer_name
  }
}
