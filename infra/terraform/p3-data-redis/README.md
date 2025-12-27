# P3 - Data services (Blob + Postgres Flexible + Azure Cache for Redis)

This folder creates DEV and PROD data resources across two subscriptions using provider aliases.

Creates (per env):
- Storage account + private containers + lifecycle rules
- Postgres Flexible Server + esendit database + baseline firewall
- Azure Cache for Redis (DEV Basic C0, PROD Standard C1)
- Stores DB admin password, DB connection URL, and Redis connection URL in the environment Key Vault

## Usage
1) Copy terraform.tfvars.example -> terraform.tfvars and edit if needed.
2) terraform init
3) terraform plan
4) terraform apply

## Notes
- Storage/Redis names include random suffixes for global uniqueness.
- Postgres firewall default is 'allow Azure services' (0.0.0.0). For PROD, set postgres_allowed_cidrs_prod ASAP.
- Private endpoints are not created here (we can add in the next phase).

### PostgreSQL SKU naming (Terraform)

Terraform's `azurerm_postgresql_flexible_server.sku_name` expects the **tier-prefixed** format (tier + VM SKU), e.g.:

- `B_Standard_B1ms` (Burstable)
- `GP_Standard_D2s_v3` or `GP_Standard_D2ds_v5` (General Purpose)
- `MO_Standard_E4s_v3` (Memory Optimized)

If you want to see what's available in your region, run:

```bash
az postgres flexible-server list-skus -l centralindia -o table
```
