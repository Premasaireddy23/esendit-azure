variable "subscription_id_dev" {
  type = string
}

variable "subscription_id_prod" {
  type = string
}

variable "name_suffix" {
  type = string
}

variable "tags" {
  type = map(string)
}

# AKS tiers
variable "aks_sku_tier_dev" {
  type    = string
  default = "Free"
}

variable "aks_sku_tier_prod" {
  type    = string
  default = "Standard"
}

# VM sizes
variable "system_vm_size_dev" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "system_vm_size_prod" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "core_vm_size_dev" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "core_vm_size_prod" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "transcode_std_vm_size_dev" {
  type    = string
  default = "Standard_F4as_v6"
}

variable "transcode_bcast_vm_size_dev" {
  type    = string
  default = "Standard_F4as_v6"
}

variable "transcode_std_vm_size_prod" {
  type    = string
  default = "Standard_F8as_v6"
}

variable "transcode_bcast_vm_size_prod" {
  type    = string
  default = "Standard_F8as_v6"
}

variable "transcode_priority_dev" {
  type    = string
  default = "Regular" # Spot may be blocked in centralindia PayG
  validation {
    condition     = contains(["Regular", "Spot"], var.transcode_priority_dev)
    error_message = "transcode_priority_dev must be Regular or Spot"
  }
}

variable "transcode_priority_prod" {
  type    = string
  default = "Regular" # keep safe default; switch to Spot only when subscription/region supports it
  validation {
    condition     = contains(["Regular", "Spot"], var.transcode_priority_prod)
    error_message = "transcode_priority_prod must be Regular or Spot"
  }
}


variable "transcode_std_max" {
  type    = number
  default = 10
}

variable "transcode_bcast_max" {
  type    = number
  default = 4
}

# AKS network
variable "service_cidr" {
  type    = string
  default = "10.240.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "10.240.0.10"
}

variable "docker_bridge_cidr" {
  type    = string
  default = "172.17.0.1/16"
}
