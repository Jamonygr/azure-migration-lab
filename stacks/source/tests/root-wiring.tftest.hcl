mock_provider "azurerm" {}
mock_provider "random" {}
variables {
  subscription_id   = "11111111-1111-4111-8111-111111111111"
  enable_monitoring = false
  foundation_manifest = {
    subscription_id                 = "11111111-1111-4111-8111-111111111111"
    environment                     = "cheap-lab"
    location                        = "westeurope"
    tenant_id                       = "22222222-2222-4222-8222-222222222222"
    suffix                          = "abc123"
    source_rg                       = "rg-source"
    target_rg                       = "rg-target"
    source_subnet_id                = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-source/providers/Microsoft.Network/virtualNetworks/vnet-source/subnets/compute"
    target_subnet_id                = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-target/providers/Microsoft.Network/virtualNetworks/vnet-target/subnets/compute"
    source_private_ip               = "10.100.1.4"
    target_private_ip               = "10.200.1.4"
    source_egress_public_ip_id      = null
    target_egress_public_ip_id      = null
    migration_identity_id           = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-shared/providers/Microsoft.ManagedIdentity/userAssignedIdentities/migration"
    migration_identity_client_id    = "44444444-4444-4444-8444-444444444444"
    migration_identity_principal_id = "55555555-5555-4555-8555-555555555555"
    private_endpoint_subnet_id      = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-target/providers/Microsoft.Network/virtualNetworks/vnet-target/subnets/private-endpoints"
    private_dns_zone_ids            = { sql = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-shared/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net" }
    storage_account_id              = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/sttest"
    staging_container_name          = "artifacts"
    file_share_name                 = "migration"
    key_vault_id                    = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-shared/providers/Microsoft.KeyVault/vaults/kvtest"
  }
  source_manifest = { private_ip = "10.100.1.4" }
}
run "source_root_manifest_contract" {
  command = plan
  assert {
    condition     = output.manifest.private_ip == "10.100.1.4" && output.manifest.migration_identity_client_id == var.foundation_manifest.migration_identity_client_id
    error_message = "Source manifest must carry static address and the stable migration identity."
  }
}
run "mismatched_environment_rejected" {
  command = plan
  variables { environment = "prod" }
  expect_failures = [var.foundation_manifest]
}