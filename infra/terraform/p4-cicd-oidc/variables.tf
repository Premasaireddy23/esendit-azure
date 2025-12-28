variable "subscription_id_dev" { type = string }
variable "subscription_id_prod" { type = string }

variable "github_org" { type = string }

# App code repo (private) - builds/pushes images
variable "github_repo_app" { type = string }

# Infra repo (public) - deploys to AKS
variable "github_repo_infra" { type = string }

# DEV branch names
variable "github_app_branch_dev" {
  type    = string
  default = "dev"
}

variable "github_infra_branch_dev" {
  type    = string
  default = "main"
}

# PROD GitHub Environment name (recommended)
variable "github_prod_environment" {
  type    = string
  default = "prod"
}

# DEV lookup targets
variable "aks_name_dev" { type = string }
variable "aks_rg_dev" { type = string }
variable "acr_name_dev" { type = string }
variable "acr_rg_dev" { type = string }

# PROD lookup targets
variable "aks_name_prod" { type = string }
variable "aks_rg_prod" { type = string }
variable "acr_name_prod" { type = string }
variable "acr_rg_prod" { type = string }
