variable "subscription_id_dev" {
  type = string
}

variable "subscription_id_prod" {
  type = string
}

variable "rg_aks_dev" {
  type = string
}

variable "aks_name_dev" {
  type = string
}

variable "rg_aks_prod" {
  type = string
}

variable "aks_name_prod" {
  type = string
}

variable "rg_kv_dev" {
  type = string
}

variable "kv_name_dev" {
  type = string
}

variable "rg_kv_prod" {
  type = string
}

variable "kv_name_prod" {
  type = string
}

variable "rotation_poll_interval" {
  type    = string
  default = "1h"
}
