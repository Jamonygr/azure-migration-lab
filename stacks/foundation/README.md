## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15.8, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.57.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.6.3 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_budget"></a> [budget](#module\_budget) | ../../modules/budget | n/a |
| <a name="module_identity"></a> [identity](#module\_identity) | ../../modules/identity | n/a |
| <a name="module_keyvault"></a> [keyvault](#module\_keyvault) | ../../modules/keyvault | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | ../../modules/monitoring | n/a |
| <a name="module_networking"></a> [networking](#module\_networking) | ../../modules/networking | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ../../modules/storage | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_backup_policy_vm.daily](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/backup_policy_vm) | resource |
| [azurerm_policy_definition.owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_private_dns_zone.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_endpoint.service](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_recovery_services_vault.backup](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/recovery_services_vault) | resource |
| [azurerm_resource_group.lab](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_resource_group_policy_assignment.owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_assignment) | resource |
| [azurerm_role_assignment.migration_blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.migration_file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.migration_secrets](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Explicit Azure subscription used for this disposable lab. | `string` | n/a | yes |
| <a name="input_allowed_rdp_cidrs"></a> [allowed\_rdp\_cidrs](#input\_allowed\_rdp\_cidrs) | Exact administrator source CIDRs; universal ranges are rejected. | `list(string)` | `[]` | no |
| <a name="input_auto_shutdown_time"></a> [auto\_shutdown\_time](#input\_auto\_shutdown\_time) | Daily VM shutdown in UTC, HHmm. | `string` | `"2000"` | no |
| <a name="input_budget_amount"></a> [budget\_amount](#input\_budget\_amount) | Monthly budget per resource group, in subscription billing currency; not a spending cap. | `number` | `25` | no |
| <a name="input_budget_emails"></a> [budget\_emails](#input\_budget\_emails) | Budget notification emails; empty disables budgets instead of using a fake address. | `list(string)` | `[]` | no |
| <a name="input_budget_start_date"></a> [budget\_start\_date](#input\_budget\_start\_date) | Optional budget start month (RFC3339). Null selects the month of first apply. | `string` | `null` | no |
| <a name="input_enable_backup"></a> [enable\_backup](#input\_enable\_backup) | Protect Windows VMs with daily seven-day backups. | `bool` | `false` | no |
| <a name="input_enable_monitoring"></a> [enable\_monitoring](#input\_enable\_monitoring) | Enable Log Analytics, Azure Monitor agent, DCR, and alerts. | `bool` | `true` | no |
| <a name="input_enable_nat"></a> [enable\_nat](#input\_enable\_nat) | Use one NAT gateway per VNet instead of NIC public IPs. | `bool` | `false` | no |
| <a name="input_enable_policy"></a> [enable\_policy](#input\_enable\_policy) | Assign a lab-scoped audit policy for ownership tags. | `bool` | `false` | no |
| <a name="input_enable_public_rdp"></a> [enable\_public\_rdp](#input\_enable\_public\_rdp) | Explicitly permit RDP from allowed\_rdp\_cidrs only; incompatible with NAT profile. | `bool` | `false` | no |
| <a name="input_enable_vm_encryption_at_host"></a> [enable\_vm\_encryption\_at\_host](#input\_enable\_vm\_encryption\_at\_host) | Opt-in after checking SKU EncryptionAtHostSupported and subscription feature registration. Never silently increase VM cost. | `bool` | `false` | no |
| <a name="input_enable_workbooks"></a> [enable\_workbooks](#input\_enable\_workbooks) | Create a migration operations workbook. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Profile and state isolation name. | `string` | `"cheap-lab"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region; unavailable SKUs must be reported, never silently replaced. | `string` | `"westeurope"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag for identifying disposable resources. | `string` | `"Lab-User"` | no |
| <a name="input_project"></a> [project](#input\_project) | Short naming prefix. | `string` | `"azmig"` | no |
| <a name="input_source_address_space"></a> [source\_address\_space](#input\_source\_address\_space) | Simulated on-premises VNet IPv4 range (prefix /16 through /22). | `string` | `"10.100.0.0/16"` | no |
| <a name="input_source_vm_size"></a> [source\_vm\_size](#input\_source\_vm\_size) | Source Windows VM size. | `string` | `"Standard_B2ms"` | no |
| <a name="input_target_address_space"></a> [target\_address\_space](#input\_target\_address\_space) | Azure target VNet IPv4 range (prefix /16 through /22). | `string` | `"10.200.0.0/16"` | no |
| <a name="input_target_vm_size"></a> [target\_vm\_size](#input\_target\_vm\_size) | Target Windows VM size. | `string` | `"Standard_B2s"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_manifest"></a> [manifest](#output\_manifest) | Nonsensitive contract for source, target, cutover, and migration tooling. |
