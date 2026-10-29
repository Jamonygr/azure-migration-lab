package main

import rego.v1

# Inspect actual saved-plan values rather than matching Terraform source text.
deny contains msg if {
    some rc in input.resource_changes
    rc.type in {"azurerm_storage_account", "azurerm_mssql_server", "azurerm_key_vault"}
    rc.change.after != null
    rc.change.after.public_network_access_enabled == true
    msg := sprintf("%s must use private data access", [rc.address])
}

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "azurerm_storage_account"
    rc.change.after.shared_access_key_enabled == true
    msg := sprintf("%s must disable shared account keys", [rc.address])
}

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "azurerm_network_security_group"
    some rule in rc.change.after.security_rule
    rule.access == "Allow"
    rule.direction == "Inbound"
    rule.source_address_prefix in {"*", "Internet", "0.0.0.0/0"}
    msg := sprintf("%s has an unrestricted inbound allow rule", [rc.address])
}

deny contains msg if {
    some rc in input.resource_changes
    rc.type == "azurerm_network_security_group"
    some rule in rc.change.after.security_rule
    rule.access == "Allow"
    rule.direction == "Inbound"
    some prefix in rule.source_address_prefixes
    prefix in {"*", "Internet", "0.0.0.0/0"}
    msg := sprintf("%s has an unrestricted inbound allowlist", [rc.address])
}

deny contains msg if {
    input.variables.environment.value == "prod"
    some rc in input.resource_changes
    rc.type == "azurerm_network_interface"
    some config in rc.change.after.ip_configuration
    config.public_ip_address_id != null
    config.public_ip_address_id != ""
    msg := sprintf("%s must not attach a public NIC IP in prod", [rc.address])
}
