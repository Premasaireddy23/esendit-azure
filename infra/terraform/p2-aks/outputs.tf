output "dev" {
  value = {
    aks_name        = azurerm_kubernetes_cluster.dev.name
    aks_rg          = azurerm_kubernetes_cluster.dev.resource_group_name
    oidc_issuer_url = azurerm_kubernetes_cluster.dev.oidc_issuer_url
  }
}

output "prod" {
  value = {
    aks_name        = azurerm_kubernetes_cluster.prod.name
    aks_rg          = azurerm_kubernetes_cluster.prod.resource_group_name
    oidc_issuer_url = azurerm_kubernetes_cluster.prod.oidc_issuer_url
  }
}
