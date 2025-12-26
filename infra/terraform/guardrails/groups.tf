resource "azuread_group" "prod_owners" {
  display_name     = "esendit-prod-owners"
  security_enabled = true
}

resource "azuread_group" "prod_ops" {
  display_name     = "esendit-prod-ops"
  security_enabled = true
}

resource "azuread_group" "prod_dev_readonly" {
  display_name     = "esendit-prod-dev-readonly"
  security_enabled = true
}
