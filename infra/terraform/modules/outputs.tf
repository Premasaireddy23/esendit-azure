output "rg_core" { value = azurerm_resource_group.core.name }
output "rg_aks"  { value = azurerm_resource_group.aks.name }
output "rg_data" { value = azurerm_resource_group.data.name }

output "vnet_id"                 { value = azurerm_virtual_network.vnet.id }
output "subnet_aks_id"           { value = azurerm_subnet.aks.id }
output "subnet_private_ep_id"    { value = azurerm_subnet.private_endpoints.id }

output "acr_id"   { value = azurerm_container_registry.acr.id }
output "acr_name" { value = azurerm_container_registry.acr.name }
output "kv_id"    { value = azurerm_key_vault.kv.id }
output "kv_name"  { value = azurerm_key_vault.kv.name }
