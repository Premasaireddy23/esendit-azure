provider "azuread" {}

# PROD subscription provider
provider "azurerm" {
  alias           = "prod"
  subscription_id = var.subscription_id_prod
  features {}
}

# DEV subscription provider
provider "azurerm" {
  alias           = "dev"
  subscription_id = var.subscription_id_dev
  features {}
}
