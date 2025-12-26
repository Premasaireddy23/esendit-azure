output "groups" {
  value = {
    prod_owners       = azuread_group.prod_owners.display_name
    prod_ops          = azuread_group.prod_ops.display_name
    prod_dev_readonly = azuread_group.prod_dev_readonly.display_name
  }
}
