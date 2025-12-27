provider "azurerm" {
  features {}
  subscription_id = var.subscription_id_dev
}

provider "azurerm" {
  alias = "prod"
  features {}
  subscription_id = var.subscription_id_prod
}
