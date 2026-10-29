variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "tags" {
  type = map(string)
}
resource "azurerm_user_assigned_identity" "migration" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
output "id" { value = azurerm_user_assigned_identity.migration.id }
output "client_id" { value = azurerm_user_assigned_identity.migration.client_id }
output "principal_id" { value = azurerm_user_assigned_identity.migration.principal_id }
