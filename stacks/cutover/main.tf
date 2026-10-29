variable "foundation_manifest" {
  type = any
}
variable "source_manifest" {
  type = any
}
variable "target_manifest" {
  type = any
}
variable "active_site" {
  description = "DNS destination. Change only through the validated cutover/rollback stages."
  type        = string
  default     = "source"
  validation {
    condition     = contains(["source", "target"], var.active_site)
    error_message = "active_site must be source or target."
  }
}
resource "azurerm_private_dns_a_record" "application" {
  name                = "app"
  zone_name           = var.foundation_manifest.private_dns_zone_name
  resource_group_name = var.foundation_manifest.private_dns_rg
  ttl                 = 30
  records             = [var.active_site == "source" ? var.source_manifest.private_ip : var.target_manifest.private_ip]
  tags                = local.tags
}
output "manifest" {
  value = {
    active_site      = var.active_site
    application_fqdn = "app.${var.foundation_manifest.private_dns_zone_name}"
    application_url  = "http://app.${var.foundation_manifest.private_dns_zone_name}"
    address          = one(azurerm_private_dns_a_record.application.records)
    ttl              = azurerm_private_dns_a_record.application.ttl
  }
}
