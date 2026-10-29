mock_provider "azurerm" {}
mock_provider "random" {}
run "windows_source_uses_secure_boot_and_explicit_egress" {
  command = plan
  module { source = "../../modules/windows-vm" }
  variables {
    name                = "vm-migration-source"
    computer_name       = "mig-source"
    resource_group_name = "rg-source"
    location            = "westeurope"
    size                = "Standard_B2ms"
    subnet_id           = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-source/providers/Microsoft.Network/virtualNetworks/vnet-source/subnets/compute"
    private_ip          = "10.100.1.4"
    public_ip_id        = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-source/providers/Microsoft.Network/publicIPAddresses/pip-source"
    identity_ids        = ["/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-shared/providers/Microsoft.ManagedIdentity/userAssignedIdentities/migration"]
    tags                = {}
  }
  assert {
    condition     = azurerm_windows_virtual_machine.this.secure_boot_enabled && azurerm_windows_virtual_machine.this.vtpm_enabled && azurerm_windows_virtual_machine.this.provision_vm_agent
    error_message = "Windows requires Trusted Launch and the agent for Run Command."
  }
  assert {
    condition     = azurerm_windows_virtual_machine.this.identity[0].type == "SystemAssigned, UserAssigned" && azurerm_dev_test_global_vm_shutdown_schedule.this.enabled
    error_message = "Source needs stable migration identity and daily shutdown cost control."
  }
}
