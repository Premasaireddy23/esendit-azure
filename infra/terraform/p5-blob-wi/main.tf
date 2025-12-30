# Read AKS to get OIDC issuer URL (no remote state dependency)
data "azurerm_kubernetes_cluster" "dev" {
  name                = var.dev_aks_name
  resource_group_name = var.dev_aks_rg
}

data "azurerm_kubernetes_cluster" "prod" {
  provider            = azurerm.prod
  name                = var.prod_aks_name
  resource_group_name = var.prod_aks_rg
}

# Read existing storage accounts (created in P3, or pre-created manually)
data "azurerm_storage_account" "dev" {
  name                = var.dev_storage_account_name
  resource_group_name = var.dev_data_rg
}

data "azurerm_storage_account" "prod" {
  provider            = azurerm.prod
  name                = var.prod_storage_account_name
  resource_group_name = var.prod_data_rg
}

# Container (private)
resource "azurerm_storage_container" "dev_media" {
  name                  = var.container_name
  storage_account_name  = data.azurerm_storage_account.dev.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "prod_media" {
  provider              = azurerm.prod
  name                  = var.container_name
  storage_account_name  = data.azurerm_storage_account.prod.name
  container_access_type = "private"
}

# UAMI per env
resource "azurerm_user_assigned_identity" "dev_storage_uami" {
  name                = "uami-esendit-dev-storage"
  location            = var.location
  resource_group_name = var.dev_core_rg
}

resource "azurerm_user_assigned_identity" "prod_storage_uami" {
  provider            = azurerm.prod
  name                = "uami-esendit-prod-storage"
  location            = var.location
  resource_group_name = var.prod_core_rg
}

# RBAC:
# - Data Contributor: read/write blobs
# - Blob Delegator: needed for generateUserDelegationKey (User Delegation SAS) :contentReference[oaicite:4]{index=4}
resource "azurerm_role_assignment" "dev_blob_data_contrib" {
  scope                = data.azurerm_storage_account.dev.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.dev_storage_uami.principal_id
}

resource "azurerm_role_assignment" "dev_blob_delegator" {
  scope                = data.azurerm_storage_account.dev.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = azurerm_user_assigned_identity.dev_storage_uami.principal_id
}

resource "azurerm_role_assignment" "prod_blob_data_contrib" {
  provider             = azurerm.prod
  scope                = data.azurerm_storage_account.prod.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.prod_storage_uami.principal_id
}

resource "azurerm_role_assignment" "prod_blob_delegator" {
  provider             = azurerm.prod
  scope                = data.azurerm_storage_account.prod.id
  role_definition_name = "Storage Blob Delegator"
  principal_id         = azurerm_user_assigned_identity.prod_storage_uami.principal_id
}

# Federated identity credentials (AKS SA -> UAMI)
# Terraform resource: azurerm_federated_identity_credential :contentReference[oaicite:5]{index=5}
locals {
  sa_backend   = "system:serviceaccount:${var.namespace}:esendit-backend-sa"
  sa_transcode = "system:serviceaccount:${var.namespace}:esendit-transcode-sa"
  sa_delivery  = "system:serviceaccount:${var.namespace}:esendit-delivery-sa"
}

resource "azurerm_federated_identity_credential" "dev_backend" {
  name                = "esendit-dev-backend"
  resource_group_name = var.dev_core_rg
  parent_id           = azurerm_user_assigned_identity.dev_storage_uami.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.dev.oidc_issuer_url
  subject             = local.sa_backend
}

resource "azurerm_federated_identity_credential" "dev_transcode" {
  name                = "esendit-dev-transcode"
  resource_group_name = var.dev_core_rg
  parent_id           = azurerm_user_assigned_identity.dev_storage_uami.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.dev.oidc_issuer_url
  subject             = local.sa_transcode
}

resource "azurerm_federated_identity_credential" "dev_delivery" {
  name                = "esendit-dev-delivery"
  resource_group_name = var.dev_core_rg
  parent_id           = azurerm_user_assigned_identity.dev_storage_uami.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.dev.oidc_issuer_url
  subject             = local.sa_delivery
}

resource "azurerm_federated_identity_credential" "prod_backend" {
  provider            = azurerm.prod
  name                = "esendit-prod-backend"
  resource_group_name = var.prod_core_rg
  parent_id           = azurerm_user_assigned_identity.prod_storage_uami.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.prod.oidc_issuer_url
  subject             = local.sa_backend
}

resource "azurerm_federated_identity_credential" "prod_transcode" {
  provider            = azurerm.prod
  name                = "esendit-prod-transcode"
  resource_group_name = var.prod_core_rg
  parent_id           = azurerm_user_assigned_identity.prod_storage_uami.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.prod.oidc_issuer_url
  subject             = local.sa_transcode
}

resource "azurerm_federated_identity_credential" "prod_delivery" {
  provider            = azurerm.prod
  name                = "esendit-prod-delivery"
  resource_group_name = var.prod_core_rg
  parent_id           = azurerm_user_assigned_identity.prod_storage_uami.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.prod.oidc_issuer_url
  subject             = local.sa_delivery
}
