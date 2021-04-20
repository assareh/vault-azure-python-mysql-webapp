data "azurerm_public_ip" "vault_ip" {
  name                = azurerm_public_ip.vault_ip.name
  resource_group_name = azurerm_virtual_machine.vault_vm.resource_group_name
}

data "azurerm_public_ip" "webapp_ip" {
  name                = azurerm_public_ip.webapp_ip.name
  resource_group_name = azurerm_virtual_machine.webapp.resource_group_name
}

output "webapp_ip" {
  value = data.azurerm_public_ip.webapp_ip.ip_address
}

output "webapp_ssh" {
  value = <<EOT

    Connect to your webapp virtual machine via SSH:

    $ ssh azureuser@${data.azurerm_public_ip.webapp_ip.ip_address}

EOT
}

output "vault_private_ip" {
  value = azurerm_network_interface.vault_nic.private_ip_address
}

output "vault_ip" {
  value = data.azurerm_public_ip.vault_ip.ip_address
}

output "vault_addr" {
  value = "http://${data.azurerm_public_ip.vault_ip.ip_address}:8200"
}

output "vault_ssh" {
  value = <<EOT

    Connect to your Vault server virtual machine via SSH:

    $ ssh azureuser@${data.azurerm_public_ip.vault_ip.ip_address}

EOT
}

/*
output "key_vault_name" {
  value = azurerm_key_vault.keyvault.name
}

output "webapp-url" {
  value = "http://${data.azurerm_public_ip.webapp_ip.ip_address}:5000"
}
*/