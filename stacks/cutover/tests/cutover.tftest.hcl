mock_provider "azurerm" {}
mock_provider "random" {}
variables {
  subscription_id     = "11111111-1111-4111-8111-111111111111"
  foundation_manifest = { private_dns_zone_name = "migration.lab.internal", private_dns_rg = "rg-shared" }
  source_manifest     = { private_ip = "10.100.1.4" }
  target_manifest     = { private_ip = "10.200.1.4" }
}
run "source_is_initial_destination" {
  command = plan
  assert {
    condition     = contains(azurerm_private_dns_a_record.application.records, "10.100.1.4") && azurerm_private_dns_a_record.application.ttl == 30
    error_message = "Initial DNS must serve the source with a 30-second TTL."
  }
}
run "cutover_only_switches_to_target" {
  command = plan
  variables { active_site = "target" }
  assert {
    condition     = contains(azurerm_private_dns_a_record.application.records, "10.200.1.4") && output.manifest.active_site == "target"
    error_message = "Cutover must route to the target and expose the resulting state."
  }
}
run "invalid_site_rejected" {
  command = plan
  variables { active_site = "other" }
  expect_failures = [var.active_site]
}
