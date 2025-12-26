############################
# Who am I (no UPN lookup)
############################
data "azuread_client_config" "current" {}

############################
# Subscriptions (canonical resource IDs)
############################
data "azurerm_subscription" "prod" {
  provider        = azurerm.prod
  subscription_id = var.subscription_id_prod
}

data "azurerm_subscription" "dev" {
  provider        = azurerm.dev
  subscription_id = var.subscription_id_dev
}

############################
# Entra ID group memberships
# Add current signed-in identity to Owners + Ops initially
############################
resource "azuread_group_member" "admin_prod_owners" {
  group_object_id  = azuread_group.prod_owners.object_id
  member_object_id = data.azuread_client_config.current.object_id
}

resource "azuread_group_member" "admin_prod_ops" {
  group_object_id  = azuread_group.prod_ops.object_id
  member_object_id = data.azuread_client_config.current.object_id
}

############################
# RBAC role assignments - PROD
############################
resource "azurerm_role_assignment" "prod_owner" {
  provider             = azurerm.prod
  scope                = data.azurerm_subscription.prod.id
  role_definition_name = "Owner"
  principal_id         = azuread_group.prod_owners.object_id
}

resource "azurerm_role_assignment" "prod_ops_contrib" {
  provider             = azurerm.prod
  scope                = data.azurerm_subscription.prod.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.prod_ops.object_id
}

resource "azurerm_role_assignment" "prod_dev_readonly" {
  provider             = azurerm.prod
  scope                = data.azurerm_subscription.prod.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.prod_dev_readonly.object_id
}

############################
# RBAC role assignments - DEV
############################
resource "azurerm_role_assignment" "dev_owner" {
  provider             = azurerm.dev
  scope                = data.azurerm_subscription.dev.id
  role_definition_name = "Owner"
  principal_id         = azuread_group.prod_owners.object_id
}

resource "azurerm_role_assignment" "dev_ops_contrib" {
  provider             = azurerm.dev
  scope                = data.azurerm_subscription.dev.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.prod_ops.object_id
}

############################
# Budgets - PROD + DEV
# IMPORTANT: subscription_id must be /subscriptions/<uuid>
############################
resource "azurerm_consumption_budget_subscription" "prod" {
  provider        = azurerm.prod
  name            = "esendit-prod-budget"
  subscription_id = data.azurerm_subscription.prod.id
  amount          = var.budget_amount_prod
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = "2030-01-01T00:00:00Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 50.0
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }
  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 80.0
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }
  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100.0
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }
}

resource "azurerm_consumption_budget_subscription" "dev" {
  provider        = azurerm.dev
  name            = "esendit-dev-budget"
  subscription_id = data.azurerm_subscription.dev.id
  amount          = var.budget_amount_dev
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = "2030-01-01T00:00:00Z"
  }

  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 80.0
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }
  notification {
    enabled        = true
    operator       = "GreaterThanOrEqualTo"
    threshold      = 100.0
    threshold_type = "Actual"
    contact_emails = var.budget_alert_emails
  }
}


############################
# Azure Policy: Allowed locations (apply to both subscriptions)
############################
data "azurerm_policy_definition" "allowed_locations" {
  provider     = azurerm.prod
  display_name = "Allowed locations"
}

resource "azurerm_subscription_policy_assignment" "allowed_locations_prod" {
  provider             = azurerm.prod
  name                 = "esendit-allowed-locations"
  subscription_id      = data.azurerm_subscription.prod.id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}

resource "azurerm_subscription_policy_assignment" "allowed_locations_dev" {
  provider             = azurerm.dev
  name                 = "esendit-allowed-locations"
  subscription_id      = data.azurerm_subscription.dev.id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}
