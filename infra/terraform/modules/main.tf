data "azurerm_client_config" "current" {}

locals {
  # NOTE: ACR/KV names must be globally unique + lowercase + no hyphens for KV.
  # Keep short to avoid name length limits.
  acr_name = "acresendit${var.env}${var.name_suffix}"
  kv_name  = "kvesendit${var.env}${var.name_suffix}"

  rg_core = "rg-esendit-${var.env}-core-wi"
  rg_aks  = "rg-esendit-${var.env}-aks-wi"
  rg_data = "rg-esendit-${var.env}-data-wi"

  vnet_name = "vnet-esendit-${var.env}-wi"
}

# --- Resource Groups (P1) ---
resource "azurerm_resource_group" "core" {
  name     = local.rg_core
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "aks" {
  name     = local.rg_aks
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "data" {
  name     = local.rg_data
  location = var.location
  tags     = var.tags
}

# --- VNet + Subnets (P1) ---
resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_aks_cidr]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_private_ep_cidr]

  # Recommended when hosting Private Endpoints in the subnet:
  private_endpoint_network_policies = "Disabled"

}

# --- Private DNS zones (pre-req for later Private Endpoints; cheap to create now) ---
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.core.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_link" {
  name                  = "blob-link"
  resource_group_name   = azurerm_resource_group.core.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.core.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_link" {
  name                  = "kv-link"
  resource_group_name   = azurerm_resource_group.core.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
}

# --- ACR (P1) ---
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.core.name
  location            = var.acr_location

  sku           = "Basic"
  admin_enabled = false
  tags          = var.tags
}

# ACR resource schema (sku/admin_enabled). :contentReference[oaicite:1]{index=1}

# --- Key Vault (P1) ---
resource "azurerm_key_vault" "kv" {
  name                = local.kv_name
  location            = azurerm_resource_group.core.location
  resource_group_name = azurerm_resource_group.core.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Prefer RBAC model (recommended), then assign roles.
  rbac_authorization_enabled = true

  # Safety defaults
  purge_protection_enabled    = true
  soft_delete_retention_days  = 90

  tags = var.tags
}

# Key Vault args (RBAC, purge protection, retention). :contentReference[oaicite:2]{index=2}

# Give KV admin to either provided principals OR the current caller
locals {
  kv_admins = length(var.kv_admin_object_ids) > 0 ? var.kv_admin_object_ids : [data.azurerm_client_config.current.object_id]
}

resource "azurerm_role_assignment" "kv_admin" {
  for_each             = toset(local.kv_admins)
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
}
