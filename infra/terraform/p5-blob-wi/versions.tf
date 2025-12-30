terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.dev_subscription_id
  tenant_id       = var.tenant_id
}

provider "azurerm" {
  alias = "prod"
  features {}
  subscription_id = var.prod_subscription_id
  tenant_id       = var.tenant_id
}
