resource "azurerm_public_ip" "vault_ip" {
  name                = "${var.prefix}-vault-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
  tags                = var.common_tags
}

resource "azurerm_network_security_group" "vault_nsg" {
  name                = "${var.prefix}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.common_tags

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Vault"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8200"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "MySQL"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "vault_nic" {
  name                = "${var.prefix}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.common_tags

  ip_configuration {
    name                          = "${var.prefix}-nic"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.vault_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "vault_nic_nsg" {
  network_interface_id      = azurerm_network_interface.vault_nic.id
  network_security_group_id = azurerm_network_security_group.vault_nsg.id
}

resource "azurerm_virtual_machine" "vault_vm" {
  name                          = "${var.prefix}-vault-vm"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  network_interface_ids         = [azurerm_network_interface.vault_nic.id]
  vm_size                       = var.vm_size
  delete_os_disk_on_termination = true
  tags                          = var.common_tags

  identity {
    type = "SystemAssigned"
  }

  storage_os_disk {
    name              = "OsDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04.0-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "${var.prefix}-vault-vm"
    admin_username = "azureuser"
    custom_data = base64encode(templatefile("${path.module}/templates/userdata-vault-server.tpl", {
      client_id           = var.client_id
      client_msi          = var.client_msi
      client_secret       = var.client_secret
      key_name            = azurerm_key_vault_key.generated.name
      license             = var.license
      resource_group_name = var.resource_group_name
      subscription_id     = var.subscription_id
      tenant_id           = var.tenant_id
      vault_name          = azurerm_key_vault.keyvault.name
      vault_namespace     = var.vault_namespace
      vault_vm_name       = "${var.prefix}-vault-vm"
    }))
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/azureuser/.ssh/authorized_keys"
      key_data = var.public_key
    }
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = var.storage_uri
  }
}

###########
# Azure Key Vault for Vault Auto Unseal
###########

data "azurerm_client_config" "current" {
}

resource "azurerm_key_vault" "keyvault" {
  name                        = "${var.prefix}-kv"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  enabled_for_deployment      = true
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  tags                        = var.common_tags

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "get",
      "list",
      "create",
      "delete",
      "update",
      "wrapKey",
      "unwrapKey",
    ]
  }

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

resource "azurerm_key_vault_key" "generated" {
  name         = "${var.prefix}-key"
  key_vault_id = azurerm_key_vault.keyvault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]
}
