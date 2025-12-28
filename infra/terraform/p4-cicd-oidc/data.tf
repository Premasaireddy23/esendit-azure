data "azurerm_client_config" "current" {}

data "azurerm_kubernetes_cluster" "dev" {
  name                = var.aks_name_dev
  resource_group_name = var.aks_rg_dev
}

data "azurerm_container_registry" "dev" {
  name                = var.acr_name_dev
  resource_group_name = var.acr_rg_dev
}

data "azurerm_kubernetes_cluster" "prod" {
  provider            = azurerm.prod
  name                = var.aks_name_prod
  resource_group_name = var.aks_rg_prod
}

data "azurerm_container_registry" "prod" {
  provider            = azurerm.prod
  name                = var.acr_name_prod
  resource_group_name = var.acr_rg_prod
}
