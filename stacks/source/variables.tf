variable "foundation_manifest" {
  description = "Foundation output manifest supplied by the orchestration script."
  type        = any
  validation {
    condition     = try(var.foundation_manifest.environment == var.environment && var.foundation_manifest.subscription_id == var.subscription_id && var.foundation_manifest.location == var.location, false)
    error_message = "Foundation environment, subscription and region must match the current profile."
  }
  validation {
    condition     = can(var.foundation_manifest.storage_account_id) && can(var.foundation_manifest.migration_identity_client_id) && can(var.foundation_manifest.private_endpoint_subnet_id)
    error_message = "Supply the complete foundation manifest; do not hand-edit individual resource IDs."
  }
}
