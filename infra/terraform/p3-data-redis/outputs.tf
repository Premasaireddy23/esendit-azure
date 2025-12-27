output "dev_storage_account_name" { value = azurerm_storage_account.dev.name }
output "prod_storage_account_name" { value = azurerm_storage_account.prod.name }

output "dev_postgres_fqdn" { value = azurerm_postgresql_flexible_server.dev.fqdn }
output "prod_postgres_fqdn" { value = azurerm_postgresql_flexible_server.prod.fqdn }

output "dev_redis_host" { value = azurerm_redis_cache.dev.hostname }
output "prod_redis_host" { value = azurerm_redis_cache.prod.hostname }
