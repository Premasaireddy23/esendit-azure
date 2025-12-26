module "prod" {
  source    = "../modules"
  providers = { azurerm = azurerm.prod }

  env          = "prod"
  location     = var.location
  name_suffix  = var.name_suffix
  acr_location = "centralindia"

  vnet_cidr              = var.prod_vnet_cidr
  subnet_aks_cidr        = var.prod_subnet_aks
  subnet_private_ep_cidr = var.prod_subnet_private_endpoints

  tags = merge(var.tags, { env = "prod", region = var.location })

  kv_admin_object_ids = var.kv_admin_object_ids_prod
}

module "dev" {
  source    = "../modules"
  providers = { azurerm = azurerm.dev }

  env          = "dev"
  location     = var.location
  name_suffix  = var.name_suffix
  acr_location = "centralindia"

  vnet_cidr              = var.dev_vnet_cidr
  subnet_aks_cidr        = var.dev_subnet_aks
  subnet_private_ep_cidr = var.dev_subnet_private_endpoints

  tags = merge(var.tags, { env = "dev", region = var.location })

  kv_admin_object_ids = var.kv_admin_object_ids_dev
}
