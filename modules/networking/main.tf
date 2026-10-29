variable "name" {
  type = string
}
variable "location" {
  type = string
}
variable "source_rg" {
  type = string
}
variable "target_rg" {
  type = string
}
variable "source_address_space" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.source_address_space)) && try(tonumber(split("/", var.source_address_space)[1]) >= 16 && tonumber(split("/", var.source_address_space)[1]) <= 22, false)
    error_message = "Use an IPv4 VNet prefix between /16 and /22 so the lab can create /24 subnets."
  }
}
variable "target_address_space" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.target_address_space)) && try(tonumber(split("/", var.target_address_space)[1]) >= 16 && tonumber(split("/", var.target_address_space)[1]) <= 22, false)
    error_message = "Use an IPv4 VNet prefix between /16 and /22 so the lab can create /24 subnets."
  }
}
variable "enable_nat" {
  type = bool
}
variable "enable_public_rdp" {
  type = bool
}
variable "allowed_rdp_cidrs" {
  type = list(string)
}
variable "tags" {
  type = map(string)
}
locals {
  source_first = sum([for i, n in split(".", cidrhost(var.source_address_space, 0)) : tonumber(n) * pow(256, 3 - i)])
  source_last  = sum([for i, n in split(".", cidrhost(var.source_address_space, -1)) : tonumber(n) * pow(256, 3 - i)])
  target_first = sum([for i, n in split(".", cidrhost(var.target_address_space, 0)) : tonumber(n) * pow(256, 3 - i)])
  target_last  = sum([for i, n in split(".", cidrhost(var.target_address_space, -1)) : tonumber(n) * pow(256, 3 - i)])
  sites = {
    source = { rg = var.source_rg, cidr = var.source_address_space }
    target = { rg = var.target_rg, cidr = var.target_address_space }
  }
}
resource "azurerm_virtual_network" "site" {
  for_each            = local.sites
  name                = "vnet-${var.name}-${each.key}"
  resource_group_name = each.value.rg
  location            = var.location
  address_space       = [each.value.cidr]
  tags                = var.tags
  lifecycle {
    precondition {
      condition     = (local.source_last < local.target_first || local.target_last < local.source_first)
      error_message = "Use non-overlapping IPv4 source/target ranges with room for compute and private endpoint subnets."
    }
    precondition {
      condition     = !var.enable_public_rdp || (length(var.allowed_rdp_cidrs) > 0 && !var.enable_nat && alltrue([for c in var.allowed_rdp_cidrs : can(cidrnetmask(c)) && tonumber(split("/", c)[1]) >= 16]))
      error_message = "Public RDP needs explicit IPv4 /16-or-narrower allowlists and a public-IP profile."
    }
  }
}
resource "azurerm_subnet" "compute" {
  for_each                        = local.sites
  name                            = "snet-compute"
  resource_group_name             = each.value.rg
  virtual_network_name            = azurerm_virtual_network.site[each.key].name
  address_prefixes                = [cidrsubnet(each.value.cidr, 24 - tonumber(split("/", each.value.cidr)[1]), 1)]
  default_outbound_access_enabled = false
}
resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = var.target_rg
  virtual_network_name              = azurerm_virtual_network.site["target"].name
  address_prefixes                  = [cidrsubnet(var.target_address_space, 24 - tonumber(split("/", var.target_address_space)[1]), 2)]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Enabled"
}
resource "azurerm_network_security_group" "site" {
  for_each            = local.sites
  name                = "nsg-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = each.value.rg
  tags                = var.tags
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  dynamic "security_rule" {
    for_each = var.enable_public_rdp ? [1] : []
    content {
      name                       = "ExplicitAdministratorRDP"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefixes    = var.allowed_rdp_cidrs
      destination_address_prefix = "*"
    }
  }
}
resource "azurerm_subnet_network_security_group_association" "compute" {
  for_each                  = local.sites
  subnet_id                 = azurerm_subnet.compute[each.key].id
  network_security_group_id = azurerm_network_security_group.site[each.key].id
}
resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.site["target"].id
}
resource "azurerm_virtual_network_peering" "peer" {
  for_each                     = local.sites
  name                         = "peer-${each.key}-to-${each.key == "source" ? "target" : "source"}"
  resource_group_name          = each.value.rg
  virtual_network_name         = azurerm_virtual_network.site[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.site[each.key == "source" ? "target" : "source"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}
resource "azurerm_public_ip" "outbound" {
  for_each            = local.sites
  name                = "pip-${var.name}-${each.key}-egress"
  location            = var.location
  resource_group_name = each.value.rg
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway" "site" {
  for_each            = var.enable_nat ? local.sites : {}
  name                = "nat-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = each.value.rg
  sku_name            = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway_public_ip_association" "site" {
  for_each             = var.enable_nat ? local.sites : {}
  nat_gateway_id       = azurerm_nat_gateway.site[each.key].id
  public_ip_address_id = azurerm_public_ip.outbound[each.key].id
}
resource "azurerm_subnet_nat_gateway_association" "site" {
  for_each       = var.enable_nat ? local.sites : {}
  subnet_id      = azurerm_subnet.compute[each.key].id
  nat_gateway_id = azurerm_nat_gateway.site[each.key].id
}
output "vnets" { value = { for k, v in azurerm_virtual_network.site : k => v.id } }
output "subnets" { value = { for k, v in azurerm_subnet.compute : k => v.id } }
output "compute_addresses" { value = { for k, v in local.sites : k => cidrhost(cidrsubnet(v.cidr, 24 - tonumber(split("/", v.cidr)[1]), 1), 4) } }
output "private_endpoint_subnet_id" { value = azurerm_subnet.private_endpoints.id }
output "nic_public_ip_ids" { value = { for k, v in azurerm_public_ip.outbound : k => (var.enable_nat ? null : v.id) } }
