# -------------------------
# DEV
# -------------------------
data "azurerm_kubernetes_cluster" "dev" {
  name                = var.aks_name_dev
  resource_group_name = var.rg_aks_dev
}

data "azurerm_key_vault" "dev" {
  name                = var.kv_name_dev
  resource_group_name = var.rg_kv_dev
}

resource "azapi_update_resource" "dev_enable_kv_csi" {
  type        = "Microsoft.ContainerService/managedClusters@2024-08-01"
  resource_id = data.azurerm_kubernetes_cluster.dev.id

  body = {
    properties = {
      addonProfiles = {
        azureKeyvaultSecretsProvider = {
          enabled = true
          config = {
            enableSecretRotation = "true"
            rotationPollInterval = var.rotation_poll_interval
          }
        }
      }
    }
  }
}

# Node RG where AKS creates addon identities
locals {
  dev_node_rg = data.azurerm_kubernetes_cluster.dev.node_resource_group
}

data "azurerm_resources" "dev_uami" {
  resource_group_name = local.dev_node_rg
  type                = "Microsoft.ManagedIdentity/userAssignedIdentities"
}

locals {
  dev_kv_csi_uami_name = one([
    for r in data.azurerm_resources.dev_uami.resources : r.name
    if can(regex("azurekeyvaultsecretsprovider", lower(r.name)))
  ])
}

data "azurerm_user_assigned_identity" "dev_kv_csi_uami" {
  name                = local.dev_kv_csi_uami_name
  resource_group_name = local.dev_node_rg

  depends_on = [azapi_update_resource.dev_enable_kv_csi]
}

resource "azurerm_role_assignment" "dev_kv_secrets_user" {
  scope                = data.azurerm_key_vault.dev.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_user_assigned_identity.dev_kv_csi_uami.principal_id

  depends_on = [azapi_update_resource.dev_enable_kv_csi]
}


# -------------------------
# PROD
# -------------------------
data "azurerm_kubernetes_cluster" "prod" {
  provider            = azurerm.prod
  name                = var.aks_name_prod
  resource_group_name = var.rg_aks_prod
}

data "azurerm_key_vault" "prod" {
  provider            = azurerm.prod
  name                = var.kv_name_prod
  resource_group_name = var.rg_kv_prod
}

resource "azapi_update_resource" "prod_enable_kv_csi" {
  provider    = azapi.prod
  type        = "Microsoft.ContainerService/managedClusters@2024-08-01"
  resource_id = data.azurerm_kubernetes_cluster.prod.id

  body = {
    properties = {
      addonProfiles = {
        azureKeyvaultSecretsProvider = {
          enabled = true
          config = {
            enableSecretRotation = "true"
            rotationPollInterval = var.rotation_poll_interval
          }
        }
      }
    }
  }
}

locals {
  prod_node_rg = data.azurerm_kubernetes_cluster.prod.node_resource_group
}

data "azurerm_resources" "prod_uami" {
  provider            = azurerm.prod
  resource_group_name = local.prod_node_rg
  type                = "Microsoft.ManagedIdentity/userAssignedIdentities"
}

locals {
  prod_kv_csi_uami_name = one([
    for r in data.azurerm_resources.prod_uami.resources : r.name
    if can(regex("azurekeyvaultsecretsprovider", lower(r.name)))
  ])
}

data "azurerm_user_assigned_identity" "prod_kv_csi_uami" {
  provider            = azurerm.prod
  name                = local.prod_kv_csi_uami_name
  resource_group_name = local.prod_node_rg

  depends_on = [azapi_update_resource.prod_enable_kv_csi]
}

resource "azurerm_role_assignment" "prod_kv_secrets_user" {
  provider             = azurerm.prod
  scope                = data.azurerm_key_vault.prod.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_user_assigned_identity.prod_kv_csi_uami.principal_id

  depends_on = [azapi_update_resource.prod_enable_kv_csi]
}
