variable "tenant_id" {
  type = string
}

variable "dev_subscription_id" {
  type = string
}

variable "prod_subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "namespace" {
  type    = string
  default = "esendit"
}

# AKS
variable "dev_aks_rg" { type = string }
variable "dev_aks_name" { type = string }
variable "prod_aks_rg" { type = string }
variable "prod_aks_name" { type = string }

# Storage RG (where your Storage Account lives / should live)
variable "dev_data_rg" { type = string }
variable "prod_data_rg" { type = string }

# Storage Accounts
# If you already created these in P3, set these names to the existing ones.
variable "dev_storage_account_name" { type = string }
variable "prod_storage_account_name" { type = string }

variable "container_name" {
  type    = string
  default = "esendit-media"
}

# Identity RG (where to create UAMI; usually core RG)
variable "dev_core_rg" { type = string }
variable "prod_core_rg" { type = string }
