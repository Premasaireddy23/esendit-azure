############################
# DEV AKS
############################
resource "azurerm_kubernetes_cluster" "dev" {
  name                = "aks-esendit-dev-${var.name_suffix}"
  location            = data.azurerm_resource_group.dev_aks_rg.location
  resource_group_name = data.azurerm_resource_group.dev_aks_rg.name
  dns_prefix          = "esendit-dev-${var.name_suffix}"

  sku_tier = var.aks_sku_tier_dev

  identity { type = "SystemAssigned" }

  # Workload Identity (Key Vault via MI later)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  role_based_access_control_enabled = true

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size_dev
    vnet_subnet_id               = local.p1.dev.subnet_aks_id
    type                         = "VirtualMachineScaleSets"
    os_disk_size_gb              = 64
    max_pods                     = 30
    only_critical_addons_enabled = true

    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 2
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "dev_core" {
  name                  = "core"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.dev.id
  vnet_subnet_id        = local.p1.dev.subnet_aks_id

  mode            = "User"
  vm_size         = var.core_vm_size_dev
  os_disk_size_gb = 128
  max_pods        = 30

  auto_scaling_enabled = true
  min_count            = 1
  max_count            = 2

  node_labels = {
    pool     = "core"
    workload = "core"
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "dev_transcode_std" {
  name                  = "tstd"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.dev.id
  vnet_subnet_id        = local.p1.dev.subnet_aks_id

  mode            = "User"
  vm_size         = var.transcode_std_vm_size_dev
  os_disk_size_gb = 256
  max_pods        = 30

  priority        = var.transcode_priority_dev
  eviction_policy = var.transcode_priority_dev == "Spot" ? "Delete" : null
  spot_max_price  = var.transcode_priority_dev == "Spot" ? -1 : null

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.transcode_std_max

  node_labels = merge(
    {
      pool     = "transcode-standard"
      class    = "standard"
      workload = "transcode"
      capacity = var.transcode_priority_dev == "Spot" ? "spot" : "ondemand"
    },
    var.transcode_priority_dev == "Spot" ? { spot = "true" } : {}
  )

  node_taints = concat(
    [
      "workload=transcode:NoSchedule",
      "class=standard:NoSchedule",
    ],
    var.transcode_priority_dev == "Spot" ? ["spot=true:NoSchedule"] : []
  )

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "dev_transcode_bcast" {
  name                  = "tbcast"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.dev.id
  vnet_subnet_id        = local.p1.dev.subnet_aks_id

  mode            = "User"
  vm_size         = var.transcode_bcast_vm_size_dev
  os_disk_size_gb = 512
  max_pods        = 20

  priority        = var.transcode_priority_dev
  eviction_policy = var.transcode_priority_dev == "Spot" ? "Delete" : null
  spot_max_price  = var.transcode_priority_dev == "Spot" ? -1 : null

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.transcode_bcast_max

  node_labels = merge(
    {
      pool     = "transcode-broadcast"
      class    = "broadcast"
      workload = "transcode"
      capacity = var.transcode_priority_dev == "Spot" ? "spot" : "ondemand"
    },
    var.transcode_priority_dev == "Spot" ? { spot = "true" } : {}
  )

  node_taints = concat(
    [
      "workload=transcode:NoSchedule",
      "class=broadcast:NoSchedule",
    ],
    var.transcode_priority_dev == "Spot" ? ["spot=true:NoSchedule"] : []
  )

  tags = var.tags
}

# Allow AKS kubelet identity to pull images from ACR
resource "azurerm_role_assignment" "dev_acr_pull" {
  scope                = local.p1.dev.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.dev.kubelet_identity[0].object_id
}

############################
# PROD AKS (same pattern)
############################
resource "azurerm_kubernetes_cluster" "prod" {
  provider            = azurerm.prod
  name                = "aks-esendit-prod-${var.name_suffix}"
  location            = data.azurerm_resource_group.prod_aks_rg.location
  resource_group_name = data.azurerm_resource_group.prod_aks_rg.name
  dns_prefix          = "esendit-prod-${var.name_suffix}"

  sku_tier = var.aks_sku_tier_prod

  identity { type = "SystemAssigned" }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  role_based_access_control_enabled = true

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size_prod
    vnet_subnet_id               = local.p1.prod.subnet_aks_id
    type                         = "VirtualMachineScaleSets"
    os_disk_size_gb              = 64
    max_pods                     = 30
    only_critical_addons_enabled = true

    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 2
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "prod_core" {
  provider              = azurerm.prod
  name                  = "core"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.prod.id
  vnet_subnet_id        = local.p1.prod.subnet_aks_id

  mode            = "User"
  vm_size         = var.core_vm_size_prod
  os_disk_size_gb = 128
  max_pods        = 30

  auto_scaling_enabled = true
  min_count            = 1
  max_count            = 3

  node_labels = {
    pool     = "core"
    workload = "core"
  }

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "prod_transcode_std" {
  provider              = azurerm.prod
  name                  = "tstd"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.prod.id
  vnet_subnet_id        = local.p1.prod.subnet_aks_id

  mode            = "User"
  vm_size         = var.transcode_std_vm_size_prod
  os_disk_size_gb = 256
  max_pods        = 30

  priority        = var.transcode_priority_prod
  eviction_policy = var.transcode_priority_prod == "Spot" ? "Delete" : null
  spot_max_price  = var.transcode_priority_prod == "Spot" ? -1 : null

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.transcode_std_max

  node_labels = merge(
    {
      pool     = "transcode-standard"
      class    = "standard"
      workload = "transcode"
      capacity = var.transcode_priority_prod == "Spot" ? "spot" : "ondemand"
    },
    var.transcode_priority_prod == "Spot" ? { spot = "true" } : {}
  )

  node_taints = concat(
    [
      "workload=transcode:NoSchedule",
      "class=standard:NoSchedule",
    ],
    var.transcode_priority_prod == "Spot" ? ["spot=true:NoSchedule"] : []
  )

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "prod_transcode_bcast" {
  provider              = azurerm.prod
  name                  = "tbcast"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.prod.id
  vnet_subnet_id        = local.p1.prod.subnet_aks_id

  mode            = "User"
  vm_size         = var.transcode_bcast_vm_size_prod
  os_disk_size_gb = 512
  max_pods        = 20

  priority        = var.transcode_priority_prod
  eviction_policy = var.transcode_priority_prod == "Spot" ? "Delete" : null
  spot_max_price  = var.transcode_priority_prod == "Spot" ? -1 : null

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.transcode_bcast_max

  node_labels = merge(
    {
      pool     = "transcode-broadcast"
      class    = "broadcast"
      workload = "transcode"
      capacity = var.transcode_priority_prod == "Spot" ? "spot" : "ondemand"
    },
    var.transcode_priority_prod == "Spot" ? { spot = "true" } : {}
  )

  node_taints = concat(
    [
      "workload=transcode:NoSchedule",
      "class=broadcast:NoSchedule",
    ],
    var.transcode_priority_prod == "Spot" ? ["spot=true:NoSchedule"] : []
  )

  tags = var.tags
}

resource "azurerm_role_assignment" "prod_acr_pull" {
  provider             = azurerm.prod
  scope                = local.p1.prod.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.prod.kubelet_identity[0].object_id
}
