data "terraform_remote_state" "p1" {
  backend = "local"
  config = {
    path = "../p1-foundation/terraform.tfstate"
  }
}

locals {
  p1 = data.terraform_remote_state.p1.outputs
}

data "azurerm_resource_group" "dev_aks_rg" {
  name = local.p1.dev.rg_aks
}

data "azurerm_resource_group" "prod_aks_rg" {
  provider = azurerm.prod
  name     = local.p1.prod.rg_aks
}
