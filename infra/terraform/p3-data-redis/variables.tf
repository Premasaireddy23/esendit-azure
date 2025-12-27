variable "subscription_id_dev" { type = string }
variable "subscription_id_prod" { type = string }

variable "location" {
  type    = string
  default = "centralindia"
}

variable "name_suffix" {
  description = "Short suffix used in resource names (e.g. esendit000)."
  type        = string
}

variable "rg_data_dev" { type = string }
variable "rg_data_prod" { type = string }

variable "rg_core_dev" { type = string }
variable "rg_core_prod" { type = string }

variable "kv_name_dev" { type = string }
variable "kv_name_prod" { type = string }

variable "postgres_admin_username" {
  type    = string
  default = "esenditadmin"
}

variable "postgres_version" {
  type    = string
  default = "16"
}

variable "postgres_sku_dev" {
  type = string
  # NOTE: For Terraform azurerm_postgresql_flexible_server, sku_name must include the tier prefix.
  # Examples: B_Standard_B1ms, GP_Standard_D2s_v3, GP_Standard_D2ds_v5, MO_Standard_E4s_v3
  default = "B_Standard_B1ms"

  validation {
    condition     = can(regex("^(B|GP|MO)_Standard_", var.postgres_sku_dev))
    error_message = "postgres_sku_dev must be in the tier+name format (e.g., B_Standard_B1ms, GP_Standard_D2s_v3)."
  }
}

variable "postgres_sku_prod" {
  type    = string
  default = "GP_Standard_D2ds_v5"

  validation {
    condition     = can(regex("^(B|GP|MO)_Standard_", var.postgres_sku_prod))
    error_message = "postgres_sku_prod must be in the tier+name format (e.g., GP_Standard_D2ds_v5, MO_Standard_E4s_v3)."
  }
}

variable "postgres_storage_mb_dev" {
  type    = number
  default = 32768
}

variable "postgres_storage_mb_prod" {
  type    = number
  default = 131072
}

variable "postgres_backup_retention_days_dev" {
  type    = number
  default = 7
}

variable "postgres_backup_retention_days_prod" {
  type    = number
  default = 14
}

variable "postgres_allowed_cidrs_dev" {
  description = "CIDRs allowed to access DEV Postgres. If empty, an 'allow Azure services' rule is created."
  type        = list(string)
  default     = []
}

variable "postgres_allowed_cidrs_prod" {
  description = "CIDRs allowed to access PROD Postgres. If empty, an 'allow Azure services' rule is created."
  type        = list(string)
  default     = []
}

variable "tags_base" {
  type = map(string)
  default = {
    app        = "esendit"
    owner      = "admin"
    costcenter = "esendit"
    region     = "centralindia"
  }
}
