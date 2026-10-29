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

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_sql"></a> [sql](#module\_sql) | ../../modules/sql | n/a |
| <a name="module_vm"></a> [vm](#module\_vm) | ../../modules/windows-vm | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_backup_protected_vm.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/backup_protected_vm) | resource |
| [azurerm_monitor_data_collection_rule_association.vm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_monitor_metric_alert.cpu](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_private_endpoint.sql](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.runtime_blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.runtime_files](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.runtime_secrets](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_virtual_machine_extension.monitor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_extension) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_foundation_manifest"></a> [foundation\_manifest](#input\_foundation\_manifest) | Foundation output manifest supplied by the orchestration script. | `any` | n/a | yes |
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
| <a name="output_manifest"></a> [manifest](#output\_manifest) | Target runtime and database contract; no credentials are exposed. |
