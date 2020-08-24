# Due to Azure API, outputs will appear following the second terraform apply
# See https://www.terraform.io/docs/providers/azurerm/r/public_ip.html#ip_address

output "private_ip" {
  value = azurerm_network_interface.vault_nic.private_ip_address
}

output "vault_https_addr" {
  value = <<HTTPS

    Please note Vault configuration will take a couple minutes to complete.
    Connect to your virtual machine via HTTPS:

    "https://${azurerm_public_ip.vault_ip.ip_address}:8200"
HTTPS
}

output "vault_ssh_addr" {
  value = <<SSH

    Connect to your virtual machine via SSH:

    $ ssh azureuser@${azurerm_public_ip.vault_ip.ip_address}
SSH
}
