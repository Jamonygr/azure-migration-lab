terraform {
  required_version = ">= 1.15.8, < 2.0.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
  backend "local" {}
}
provider "azurerm" {
  # Subscription bootstrap registers providers; Reader-only plans must never register them.
  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
  features {
    resource_group { prevent_deletion_if_contains_resources = true }
    key_vault { purge_soft_delete_on_destroy = true }
    recovery_service {
      purge_protected_items_from_vault_on_destroy          = true
      vm_backup_stop_protection_and_retain_data_on_destroy = false
    }
  }
}
