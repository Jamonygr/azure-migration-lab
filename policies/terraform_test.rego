package main

import rego.v1

test_private_storage_allowed if {
    count(deny) == 0 with input as {"resource_changes": [{"address":"storage","type":"azurerm_storage_account","change":{"after":{"public_network_access_enabled":false,"shared_access_key_enabled":false}}}]}
}
test_public_storage_rejected if {
    count(deny) == 2 with input as {"resource_changes": [{"address":"storage","type":"azurerm_storage_account","change":{"after":{"public_network_access_enabled":true,"shared_access_key_enabled":true}}}]}
}
test_internet_allow_rejected if {
    count(deny) == 1 with input as {"resource_changes": [{"address":"nsg","type":"azurerm_network_security_group","change":{"after":{"security_rule":[{"access":"Allow","direction":"Inbound","source_address_prefix":"Internet"}]}}}]}
}
test_allowlist_bypass_rejected if {
    count(deny) == 1 with input as {"resource_changes": [{"address":"nsg","type":"azurerm_network_security_group","change":{"after":{"security_rule":[{"access":"Allow","direction":"Inbound","source_address_prefixes":["0.0.0.0/0"]}]}}}]}
}
test_prod_public_ip_rejected if {
    count(deny) == 1 with input as {"variables":{"environment":{"value":"prod"}},"resource_changes":[{"address":"nic","type":"azurerm_network_interface","change":{"after":{"ip_configuration":[{"public_ip_address_id":"/subscriptions/example/publicIPAddresses/pip"}]}}}]}
}
test_destroy_allowed if {
    count(deny) == 0 with input as {"resource_changes": [{"address":"storage","type":"azurerm_storage_account","change":{"after":null}}]}
}
