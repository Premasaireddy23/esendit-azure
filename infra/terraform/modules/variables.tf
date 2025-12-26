variable "env"         { type = string }   # dev | prod
variable "location"    { type = string }   # westindia
variable "name_suffix" { type = string }

variable "vnet_cidr"             { type = string }
variable "subnet_aks_cidr"       { type = string }
variable "subnet_private_ep_cidr" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}


variable "kv_admin_object_ids" {
  type    = list(string)
  default = []
}

variable "acr_location" {
  type        = string
  description = "Location for ACR (ACR is not available in some regions like westindia)"
  default     = "centralindia"
}
