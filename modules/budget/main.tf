variable "resource_groups" {
  type = map(string)
}
variable "amount" {
  type = number
}
variable "emails" {
  type = list(string)
}
variable "start_date" {
  type = string
}
resource "azurerm_consumption_budget_resource_group" "this" {
  for_each          = length(var.emails) > 0 ? var.resource_groups : {}
  name              = "migration-monthly-budget"
  resource_group_id = each.value
  amount            = var.amount
  time_grain        = "Monthly"
  time_period {
    start_date = coalesce(var.start_date, formatdate("YYYY-MM-01'T'00:00:00'Z'", plantimestamp()))
  }
  lifecycle {
    ignore_changes = [time_period[0].start_date]
  }
  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_emails = var.emails
  }
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"
    contact_emails = var.emails
  }
}
