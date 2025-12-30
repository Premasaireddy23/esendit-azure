output "dev_storage_uami_client_id" {
  value = azurerm_user_assigned_identity.dev_storage_uami.client_id
}

output "prod_storage_uami_client_id" {
  value = azurerm_user_assigned_identity.prod_storage_uami.client_id
}

output "container_name" {
  value = var.container_name
}
