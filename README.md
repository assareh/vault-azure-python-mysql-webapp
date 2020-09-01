# Dynamic Secrets Retrieval in Microsoft Azure App Service with HashiCorp Vault

This HashiCorp [Terraform](https://terraform.io) and [Vault](https://vaultproject.io) demo includes the following:
1. A Python webapp running on Azure App Service (code is [here](https://github.com/assareh/transit-app-example/))
2. A MySQL database used by the webapp (running as a Docker container on the Vault demo VM)
3. A Vault demo VM

This demo includes:
* Azure and JWT auth methods and includes Vault auto unseal using Azure Key Vault
* Azure machine identity
* Database secret engine with MySQL
* Dynamic credentials for MySQL
* Transit and Transform secret engines
* Encryption as a service

## Prequisites / Dependencies
### Terraform variables
A few of the Terraform variables in this configuration have defaults that you can use. Others are required and must be configured. The variables are documented via the descriptions in the [variables.tf](variables.tf) file, so we won't repeat the definitions here. The variables you must define do not have defaults defined in `variables.tf`. The variables you must define are listed in the [terraform.tfvars.example](terraform.tfvars.example). You can make a copy of this file and save it as `terraform.tfvars`, or you can define these variables as `TF_VAR_<variable_name>`.

## Running this Terraform code
Please don't store credentials in plain text and please do NOT check them into GitHub or any other VCS provider, be it public or privately hosted!

### Initialize Terraform
```
terraform init
```

### Plan
```
terraform plan
```

### Apply
```
terraform apply
```

### Outputs
* `vault_https_addr` - When you run Terraform, you'll get the public web address of the Vault instance that you've provisioned.
* `vault_ssh_addr` - When you run Terraform, you'll get the public SSH address of the Vault instance that you've provisioned.
* `webapp_url` - When you run Terraform, you'll get the public web address of the web app that you've provisioned.

## Accessing the instance
You can SSH into the instance that was provisioned via the `vault_ssh_addr` output which provides the command with username using the SSH key you provided.

## Accessing Vault
When Vault is initialized, the initial root token is stored in the `/home/azureuser/root_token` file and the recovery key is stored in the `/home/azureuser/recovery_key` file. Additionally, the initial root token is saved as the VAULT_ROOT_TOKEN environment variable in the `/etc/vault.d/vaultrc` file. You can source this file in order to interact with Vault on the instance.

```
sudo su -
. /etc/vault.d/vaultrc
vault status
VAULT_TOKEN=$VAULT_ROOT_TOKEN vault read sys/license
```

## Notes:
* The Vault VM takes a few minutes to configure after provisioning has completed.
* The web app on Azure App Service takes a few minutes to spin up the first time you try to view it.
* Due to the way IP addresses are assigned in Azure, outputs will appear following the second terraform apply. Per https://www.terraform.io/docs/providers/azurerm/r/public_ip.html#ip_address
* If you'd like to access the Vault demo VM directly, the root token will be saved in the azureuser home folder of the Vault demo VM.

## Troubleshooting
The purpose of this configuration is to allow you to provision Vault Enterprise fully unattended. If something goes wrong, you can examine the following items to see what may have gone wrong.

### Where you ran Terraform
```
terraform show
```

### On the instance
* Userdata install and configure script logs in `/var/log/user-data.log`
* Vault configuration: `/etc/vault.d/vault.hcl`
* Vault PKI certs: /opt/vault/tls/
* Vault data: /opt/vault/data/
* Vault audit log in /var/log/vault_audit.log
* You can view the webapp logs using the Azure CLI with `az webapp log tail` after enabling [logging](https://docs.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs), or in the Azure Portal on the App Service > Container Settings pane.
