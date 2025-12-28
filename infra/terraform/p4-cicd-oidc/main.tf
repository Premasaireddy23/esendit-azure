############################
# DEV GitHub OIDC App/SP
############################

resource "azuread_application" "gha_dev" {
  display_name = "esendit-gha-dev"
}

resource "azuread_service_principal" "gha_dev" {
  client_id = azuread_application.gha_dev.client_id
}

# DEV: allow App repo (esendit) on branch dev
resource "azuread_application_federated_identity_credential" "dev_app_branch" {
  application_id = azuread_application.gha_dev.id
  display_name   = "dev-app-branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo_app}:ref:refs/heads/${var.github_app_branch_dev}"
}

# DEV: allow Infra repo (esendit-azure) on branch main
resource "azuread_application_federated_identity_credential" "dev_infra_branch" {
  application_id = azuread_application.gha_dev.id
  display_name   = "dev-infra-branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo_infra}:ref:refs/heads/${var.github_infra_branch_dev}"
}

# DEV permissions: push to DEV ACR
resource "azurerm_role_assignment" "dev_acr_push" {
  scope                = data.azurerm_container_registry.dev.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.gha_dev.object_id
}

# DEV permissions: manage DEV AKS (get admin creds + kubectl apply)
resource "azurerm_role_assignment" "dev_aks_cluster_admin" {
  scope                = data.azurerm_kubernetes_cluster.dev.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = azuread_service_principal.gha_dev.object_id
}

# DEV: allow listing user credentials
resource "azurerm_role_assignment" "dev_aks_cluster_user" {
  scope                = data.azurerm_kubernetes_cluster.dev.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.gha_dev.object_id
}

############################
# PROD GitHub OIDC App/SP
############################

resource "azuread_application" "gha_prod" {
  display_name = "esendit-gha-prod"
}

resource "azuread_service_principal" "gha_prod" {
  client_id = azuread_application.gha_prod.client_id
}

# PROD: allow App repo using GitHub Environment "prod"
resource "azuread_application_federated_identity_credential" "prod_app_env" {
  application_id = azuread_application.gha_prod.id
  display_name   = "prod-app-env"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo_app}:environment:${var.github_prod_environment}"
}

# PROD: allow Infra repo using GitHub Environment "prod"
resource "azuread_application_federated_identity_credential" "prod_infra_env" {
  application_id = azuread_application.gha_prod.id
  display_name   = "prod-infra-env"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo_infra}:environment:${var.github_prod_environment}"
}

# PROD permissions: push to PROD ACR
resource "azurerm_role_assignment" "prod_acr_push" {
  provider             = azurerm.prod
  scope                = data.azurerm_container_registry.prod.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.gha_prod.object_id
}

# PROD permissions: manage PROD AKS
resource "azurerm_role_assignment" "prod_aks_cluster_admin" {
  provider             = azurerm.prod
  scope                = data.azurerm_kubernetes_cluster.prod.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = azuread_service_principal.gha_prod.object_id
}

# PROD: allow listing user credentials
resource "azurerm_role_assignment" "prod_aks_cluster_user" {
  provider             = azurerm.prod
  scope                = data.azurerm_kubernetes_cluster.prod.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.gha_prod.object_id
}