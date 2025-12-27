data "azurerm_resource_group" "dev_data" {
  name = var.rg_data_dev
}

data "azurerm_resource_group" "prod_data" {
  provider = azurerm.prod
  name     = var.rg_data_prod
}

data "azurerm_key_vault" "dev" {
  name                = var.kv_name_dev
  resource_group_name = var.rg_core_dev
}

data "azurerm_key_vault" "prod" {
  provider            = azurerm.prod
  name                = var.kv_name_prod
  resource_group_name = var.rg_core_prod
}

locals {
  dev_tags  = merge(var.tags_base, { env = "dev" })
  prod_tags = merge(var.tags_base, { env = "prod" })
}

# -------------------------
# Storage Accounts + Containers
# -------------------------
resource "random_string" "dev_sa" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

resource "random_string" "prod_sa" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

# Storage account names must be globally unique, 3-24 chars, lowercase & numbers only
resource "azurerm_storage_account" "dev" {
  name                            = "stesenditdev${random_string.dev_sa.result}"
  resource_group_name             = data.azurerm_resource_group.dev_data.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = local.dev_tags
}

resource "azurerm_storage_account" "prod" {
  provider                        = azurerm.prod
  name                            = "stesenditprod${random_string.prod_sa.result}"
  resource_group_name             = data.azurerm_resource_group.prod_data.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = local.prod_tags
}

locals {
  containers = toset(["uploads", "outputs", "thumbnails", "temp", "logs"])
}

resource "azurerm_storage_container" "dev" {
  for_each              = local.containers
  name                  = each.value
  storage_account_id    = azurerm_storage_account.dev.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "prod" {
  provider              = azurerm.prod
  for_each              = local.containers
  name                  = each.value
  storage_account_id    = azurerm_storage_account.prod.id
  container_access_type = "private"
}

# Lifecycle policies
resource "azurerm_storage_management_policy" "dev" {
  storage_account_id = azurerm_storage_account.dev.id

  rule {
    name    = "temp-delete-7d"
    enabled = true

    filters {
      prefix_match = ["temp/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 7
      }
    }
  }

  rule {
    name    = "logs-delete-30d"
    enabled = true

    filters {
      prefix_match = ["logs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }

  rule {
    name    = "outputs-cool-30d"
    enabled = true

    filters {
      prefix_match = ["outputs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }
    }
  }
}


resource "azurerm_storage_management_policy" "prod" {
  storage_account_id = azurerm_storage_account.prod.id

  rule {
    name    = "temp-delete-7d"
    enabled = true

    filters {
      prefix_match = ["temp/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 7
      }
    }
  }

  rule {
    name    = "logs-delete-30d"
    enabled = true

    filters {
      prefix_match = ["logs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }

  rule {
    name    = "outputs-cool-30d"
    enabled = true

    filters {
      prefix_match = ["outputs/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = 365
      }
    }
  }
}


# -------------------------
# Postgres Flexible Server
# -------------------------
resource "random_password" "pg_dev" {
  length  = 24
  special = true
}

resource "random_password" "pg_prod" {
  length  = 28
  special = true
}

resource "azurerm_postgresql_flexible_server" "dev" {
  name                = "pg-esendit-dev-${var.name_suffix}"
  resource_group_name = data.azurerm_resource_group.dev_data.name
  location            = var.location
  version             = var.postgres_version

  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.pg_dev.result

  sku_name   = var.postgres_sku_dev
  storage_mb = var.postgres_storage_mb_dev

  backup_retention_days         = var.postgres_backup_retention_days_dev
  public_network_access_enabled = true

  tags = local.dev_tags
  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server" "prod" {
  provider            = azurerm.prod
  name                = "pg-esendit-prod-${var.name_suffix}"
  resource_group_name = data.azurerm_resource_group.prod_data.name
  location            = var.location
  version             = var.postgres_version

  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.pg_prod.result

  sku_name   = var.postgres_sku_prod
  storage_mb = var.postgres_storage_mb_prod

  backup_retention_days         = var.postgres_backup_retention_days_prod
  public_network_access_enabled = true

  tags = local.prod_tags
  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "dev_app" {
  name      = "esendit"
  server_id = azurerm_postgresql_flexible_server.dev.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_database" "prod_app" {
  provider  = azurerm.prod
  name      = "esendit"
  server_id = azurerm_postgresql_flexible_server.prod.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Firewall rules
resource "azurerm_postgresql_flexible_server_firewall_rule" "dev_allow_azure" {
  count            = length(var.postgres_allowed_cidrs_dev) == 0 ? 1 : 0
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.dev.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "prod_allow_azure" {
  provider         = azurerm.prod
  count            = length(var.postgres_allowed_cidrs_prod) == 0 ? 1 : 0
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.prod.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Store DB creds in Key Vault
resource "azurerm_key_vault_secret" "dev_pg_admin" {
  name         = "pg-admin-password"
  value        = random_password.pg_dev.result
  key_vault_id = data.azurerm_key_vault.dev.id
  tags         = local.dev_tags
}

resource "azurerm_key_vault_secret" "prod_pg_admin" {
  provider     = azurerm.prod
  name         = "pg-admin-password"
  value        = random_password.pg_prod.result
  key_vault_id = data.azurerm_key_vault.prod.id
  tags         = local.prod_tags
}

locals {
  dev_pg_conn  = "postgresql://${var.postgres_admin_username}:${urlencode(random_password.pg_dev.result)}@${azurerm_postgresql_flexible_server.dev.fqdn}:5432/esendit?sslmode=require"
  prod_pg_conn = "postgresql://${var.postgres_admin_username}:${urlencode(random_password.pg_prod.result)}@${azurerm_postgresql_flexible_server.prod.fqdn}:5432/esendit?sslmode=require"
}

resource "azurerm_key_vault_secret" "dev_pg_conn" {
  name         = "pg-connection-url"
  value        = local.dev_pg_conn
  key_vault_id = data.azurerm_key_vault.dev.id
  tags         = local.dev_tags
}

resource "azurerm_key_vault_secret" "prod_pg_conn" {
  provider     = azurerm.prod
  name         = "pg-connection-url"
  value        = local.prod_pg_conn
  key_vault_id = data.azurerm_key_vault.prod.id
  tags         = local.prod_tags
}

# -------------------------
# Azure Cache for Redis
# -------------------------
resource "random_string" "dev_redis" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

resource "random_string" "prod_redis" {
  length  = 6
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_redis_cache" "dev" {
  name                = "redis-esendit-dev-${random_string.dev_redis.result}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.dev_data.name

  capacity             = 0
  family               = "C"
  sku_name             = "Basic"
  non_ssl_port_enabled = false
  minimum_tls_version  = "1.2"

  redis_configuration {}
  tags = local.dev_tags
}

resource "azurerm_redis_cache" "prod" {
  provider            = azurerm.prod
  name                = "redis-esendit-prod-${random_string.prod_redis.result}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.prod_data.name

  capacity             = 1
  family               = "C"
  sku_name             = "Standard"
  non_ssl_port_enabled = false
  minimum_tls_version  = "1.2"

  redis_configuration {}
  tags = local.prod_tags
}

locals {
  dev_redis_conn  = "rediss://:${azurerm_redis_cache.dev.primary_access_key}@${azurerm_redis_cache.dev.hostname}:${azurerm_redis_cache.dev.ssl_port}"
  prod_redis_conn = "rediss://:${azurerm_redis_cache.prod.primary_access_key}@${azurerm_redis_cache.prod.hostname}:${azurerm_redis_cache.prod.ssl_port}"
}

resource "azurerm_key_vault_secret" "dev_redis_conn" {
  name         = "redis-connection-url"
  value        = local.dev_redis_conn
  key_vault_id = data.azurerm_key_vault.dev.id
  tags         = local.dev_tags
}

resource "azurerm_key_vault_secret" "prod_redis_conn" {
  provider     = azurerm.prod
  name         = "redis-connection-url"
  value        = local.prod_redis_conn
  key_vault_id = data.azurerm_key_vault.prod.id
  tags         = local.prod_tags
}