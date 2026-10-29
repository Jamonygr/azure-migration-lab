output "manifest" {
  description = "Source VM contract; migration identity remains foundation-owned after source retirement."
  value = merge(module.vm.manifest, {
    migration_identity_client_id    = var.foundation_manifest.migration_identity_client_id
    migration_identity_principal_id = var.foundation_manifest.migration_identity_principal_id
    application_url                 = "http://${module.vm.manifest.private_ip}"
  })
}
