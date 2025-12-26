provider "azurerm" {
  alias           = "prod"
  subscription_id = var.subscription_id_prod
  features {}
}

provider "azurerm" {
  alias           = "dev"
  subscription_id = var.subscription_id_dev
  features {}
}
