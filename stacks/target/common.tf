variable "subscription_id" {
  description = "Explicit Azure subscription used for this disposable lab."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID."
  }
}
variable "environment" {
  description = "Profile and state isolation name."
  type        = string
  default     = "cheap-lab"
  validation {
    condition     = contains(["cheap-lab", "dev", "lab", "prod"], var.environment)
    error_message = "Choose cheap-lab, dev, lab, or prod."
  }
}
variable "location" {
  description = "Azure region; unavailable SKUs must be reported, never silently replaced."
  type        = string
  default     = "westeurope"
}
variable "owner" {
  description = "Owner tag for identifying disposable resources."
  type        = string
  default     = "Lab-User"
}
variable "project" {
  description = "Short naming prefix."
  type        = string
  default     = "azmig"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,7}$", var.project))
    error_message = "project must contain 3-8 lowercase alphanumeric characters, starting with a letter."
  }
}
variable "source_vm_size" {
  description = "Source Windows VM size."
  type        = string
  default     = "Standard_B2ms"
}
variable "target_vm_size" {
  description = "Target Windows VM size."
  type        = string
  default     = "Standard_B2s"
}
variable "enable_nat" {
  description = "Use one NAT gateway per VNet instead of NIC public IPs."
  type        = bool
  default     = false
}
variable "enable_monitoring" {
  description = "Enable Log Analytics, Azure Monitor agent, DCR, and alerts."
  type        = bool
  default     = true
}
variable "enable_workbooks" {
  description = "Create a migration operations workbook."
  type        = bool
  default     = false
}
variable "enable_backup" {
  description = "Protect Windows VMs with daily seven-day backups."
  type        = bool
  default     = false
}
variable "enable_policy" {
  description = "Assign a lab-scoped audit policy for ownership tags."
  type        = bool
  default     = false
}
variable "budget_amount" {
  description = "Monthly budget per resource group, in subscription billing currency; not a spending cap."
  type        = number
  default     = 25
  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be positive."
  }
}
variable "budget_emails" {
  description = "Budget notification emails; empty disables budgets instead of using a fake address."
  type        = list(string)
  default     = []
}
variable "budget_start_date" {
  description = "Optional budget start month (RFC3339). Null selects the month of first apply."
  type        = string
  default     = null
}
variable "enable_public_rdp" {
  description = "Explicitly permit RDP from allowed_rdp_cidrs only; incompatible with NAT profile."
  type        = bool
  default     = false
}
variable "allowed_rdp_cidrs" {
  description = "Exact administrator source CIDRs; universal ranges are rejected."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.allowed_rdp_cidrs : can(cidrnetmask(cidr)) && !contains(["0.0.0.0/0", "0.0.0.0/1", "128.0.0.0/1"], cidr)])
    error_message = "Each RDP source must be a valid restricted IPv4 CIDR."
  }
}
variable "source_address_space" {
  description = "Simulated on-premises VNet IPv4 range (prefix /16 through /22)."
  type        = string
  default     = "10.100.0.0/16"
}
variable "target_address_space" {
  description = "Azure target VNet IPv4 range (prefix /16 through /22)."
  type        = string
  default     = "10.200.0.0/16"
}
variable "auto_shutdown_time" {
  description = "Daily VM shutdown in UTC, HHmm."
  type        = string
  default     = "2000"
}
locals {
  name = "${var.project}-${var.environment}"
  tags = { Project = var.project, Environment = var.environment, Owner = var.owner, ManagedBy = "Terraform", Purpose = "MigrationLearning" }
}

variable "enable_vm_encryption_at_host" {
  description = "Opt-in after checking SKU EncryptionAtHostSupported and subscription feature registration. Never silently increase VM cost."
  type        = bool
  default     = false
}
