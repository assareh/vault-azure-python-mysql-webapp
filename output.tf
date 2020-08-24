# Due to Azure API, outputs will appear following the second terraform apply
# See https://www.terraform.io/docs/providers/azurerm/r/public_ip.html#ip_address

output "vault_https_addr" {
  value = module.vault-demo-vm.vault_https_addr
}

output "vault_ssh_addr" {
  value = module.vault-demo-vm.vault_ssh_addr
}

output "webapp_url" {
  value = "https://${azurerm_app_service.appsvc.default_site_hostname}"
}
