# ------------------------------------------------------------------
# monitoring.tf - Phase 5: observability, per environment.
#
# A NEW file alongside main.tf (Terraform reads all .tf files in the
# folder as one config) - so nothing in main.tf gets replaced except
# one attribute noted below. Each environment gets its own workspace,
# action group, and alert, consistent with the isolation model.
# ------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "law-container-demo-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# NOTE - one edit required in main.tf, not here: the Container Apps
# environment must send its logs to this workspace. Add to the
# azurerm_container_app_environment resource:
#
#   logs_destination           = "log-analytics"
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
#
# HEADS UP: this attribute forces REPLACEMENT of the environment, and
# the container app inside it - the plan will show destroy/recreate
# for both, per environment. Dev: fine. Prod: brief downtime during
# the apply (minutes). Read the plan knowingly at the gate.

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-container-demo-${var.environment_name}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "cdemo${var.environment_name}" # max 12 chars
  tags                = local.tags

  email_receiver {
    name                    = "primary-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# The alert: 5xx responses from the app. The /identity endpoint
# returns 503 when identity-based access fails - so this alert fires
# on exactly the failure mode Phase 4 introduced, and the fire drill
# exercises it by breaking that access (see README).
resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-container-demo-${var.environment_name}-5xx"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.this.id]
  description         = "Container app is returning 5xx responses (${var.environment_name})."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }

  tags = local.tags
}
