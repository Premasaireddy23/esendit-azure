variable "subscription_id_prod" {
  type        = string
  description = "Prod subscription ID"
}

variable "subscription_id_dev" {
  type        = string
  description = "Dev subscription ID"
}

variable "location" {
  type        = string
  description = "Primary region for resources"
  default     = "centralindia"
}

# Must be lowercase + numbers, used to make ACR/KV names globally unique
variable "name_suffix" {
  type        = string
  description = "Short unique suffix like 'a1b2' (lowercase/numbers)"
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    app = "esendit"
  }
}

variable "prod_vnet_cidr" {
  type        = string
  description = "Prod VNet CIDR"
  default     = "10.61.0.0/16"
}

variable "dev_vnet_cidr" {
  type        = string
  description = "Dev VNet CIDR"
  default     = "10.60.0.0/16"
}

variable "prod_subnet_aks" {
  type        = string
  description = "Prod AKS subnet CIDR"
  default     = "10.61.0.0/20"
}

variable "prod_subnet_private_endpoints" {
  type        = string
  description = "Prod Private Endpoints subnet CIDR"
  default     = "10.61.16.0/24"
}

variable "dev_subnet_aks" {
  type        = string
  description = "Dev AKS subnet CIDR"
  default     = "10.60.0.0/20"
}

variable "dev_subnet_private_endpoints" {
  type        = string
  description = "Dev Private Endpoints subnet CIDR"
  default     = "10.60.16.0/24"
}

variable "kv_admin_object_ids_prod" {
  type        = list(string)
  description = "Optional: list of object IDs (users/groups/SPs) to get Key Vault Administrator role in prod"
  default     = []
}

variable "kv_admin_object_ids_dev" {
  type        = list(string)
  description = "Optional: list of object IDs (users/groups/SPs) to get Key Vault Administrator role in dev"
  default     = []
}
