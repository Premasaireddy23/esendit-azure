output "dev_azure_client_id" {
  value = azuread_application.gha_dev.client_id
}

output "prod_azure_client_id" {
  value = azuread_application.gha_prod.client_id
}

output "azure_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id_dev" {
  value = var.subscription_id_dev
}

output "azure_subscription_id_prod" {
  value = var.subscription_id_prod
}
