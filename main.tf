provider "azurerm" {
  version = "~> 2.0"
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.common_tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.common_tags
}

resource "azurerm_subnet" "vm_subnet" {
  name                 = "${var.prefix}-vm-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "appsvc_subnet" {
  name                 = "${var.prefix}-appsvc-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Web"]

  delegation {
    name = "appservice_delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_storage_account" "storageaccount" {
  name                     = "sa${random_id.sa.hex}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.common_tags
}

resource "random_id" "sa" {
  byte_length = 6
}

module "vault-demo-vm" {
  source = "./modules/vault-demo-vm"

  client_id           = var.client_id
  client_msi          = azurerm_app_service.appsvc.identity.0.principal_id
  client_secret       = var.client_secret
  common_tags         = var.common_tags
  license             = var.license
  location            = var.location
  prefix              = var.prefix
  public_key          = var.public_key
  resource_group_name = azurerm_resource_group.rg.name
  storage_uri         = azurerm_storage_account.storageaccount.primary_blob_endpoint
  subnet_id           = azurerm_subnet.vm_subnet.id
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  vault_namespace     = var.vault_namespace
  vm_size             = var.vm_size
}

resource "azurerm_app_service_plan" "asp" {
  name                = "${var.prefix}-asp"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.common_tags
  kind                = "Linux"
  reserved            = true

  sku {
    tier = regex("[^\\/]*$", var.appserviceplantier)
    size = regex("[A-Z][1]", var.appserviceplantier)
  }
}

resource "azurerm_app_service" "appsvc" {
  name                = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.asp.id
  tags                = var.common_tags
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    app_command_line = ""
    linux_fx_version = "DOCKER|${var.appservicedocker}"
  }

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"      = azurerm_application_insights.appinsights.instrumentation_key
    "DOCKER_REGISTRY_SERVER_URL"          = "https://index.docker.io"
    "PORT"                                = "5000"
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "VAULT_ADDR"                          = "https://${module.vault-demo-vm.private_ip}:8200"
    "VAULT_NAMESPACE"                     = var.vault_namespace
    "VAULT_TRANSIT_PATH"           = "data_protection/transit"
    "VAULT_TRANSFORM_PATH"         = "data_protection/transform"
    "VAULT_TRANSFORM_MASKING_PATH" = "data_protection/masking/transform"
    "VAULT_DATABASE_CREDS_PATH"    = "data_protection/database/creds/vault-demo-app-long"
    "MYSQL_ADDR"                   = "${module.vault-demo-vm.private_ip}"
  }
}

resource "azurerm_application_insights" "appinsights" {
  name                = "${var.prefix}-appinsights"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
}

resource "azurerm_app_service_virtual_network_swift_connection" "vnetint" {
  app_service_id = azurerm_app_service.appsvc.id
  subnet_id      = azurerm_subnet.appsvc_subnet.id
}
