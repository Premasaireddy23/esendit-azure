terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id_dev
  features {}
}

provider "azurerm" {
  alias           = "prod"
  subscription_id = var.subscription_id_prod
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id_dev
}

provider "azapi" {
  alias           = "prod"
  subscription_id = var.subscription_id_prod
}
