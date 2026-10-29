variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "enable_workbooks" {
  type = bool
}
variable "tags" {
  type = map(string)
}
resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5
  tags                = var.tags
}
resource "azurerm_monitor_data_collection_rule" "windows" {
  name                = "dcr-${var.name}-windows"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Windows"
  tags                = var.tags
  destinations {
    log_analytics {
      name                  = "workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }
  data_sources {
    performance_counter {
      name                          = "performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["\\Processor(_Total)\\% Processor Time", "\\Memory\\Available MBytes"]
    }
    windows_event_log {
      name           = "system"
      streams        = ["Microsoft-Event"]
      x_path_queries = ["System!*[System[(Level=1 or Level=2 or Level=3)]]", "Application!*[System[(Level=1 or Level=2)]]"]
    }
  }
  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Event"]
    destinations = ["workspace"]
  }
}
resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${var.name}"
  resource_group_name = var.resource_group_name
  short_name          = "migration"
  tags                = var.tags
  # Alerts are visible in Azure Monitor. Budget email delivery is configured independently.
}
resource "random_uuid" "workbook" { count = var.enable_workbooks ? 1 : 0 }
resource "azurerm_application_insights_workbook" "this" {
  count               = var.enable_workbooks ? 1 : 0
  name                = random_uuid.workbook[0].result
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Migration lab validation and operations"
  tags                = var.tags
  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      { type = 1, name = "overview", content = { json = "# Migration lab operations\nVM health is infrastructure evidence. Use migration validation reports to prove SQL and file integrity." } },
      { type = 3, name = "heartbeat", content = { version = "KqlItem/1.0", query = "Heartbeat | summarize LastSeen=max(TimeGenerated) by Computer | order by LastSeen desc", size = 0, title = "VM heartbeat", queryType = 0, resourceType = "microsoft.operationalinsights/workspaces", crossComponentResources = [azurerm_log_analytics_workspace.this.id] } },
      { type = 3, name = "cpu", content = { version = "KqlItem/1.0", query = "Perf | where CounterName == '% Processor Time' | summarize CPU=avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | render timechart", size = 0, title = "Processor usage", queryType = 0, resourceType = "microsoft.operationalinsights/workspaces", crossComponentResources = [azurerm_log_analytics_workspace.this.id] } }
    ]
  })
}
output "workspace_id" { value = azurerm_log_analytics_workspace.this.id }
output "data_collection_rule_id" { value = azurerm_monitor_data_collection_rule.windows.id }
output "action_group_id" { value = azurerm_monitor_action_group.this.id }
