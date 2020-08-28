# Dynamic Secrets Retrieval in Microsoft Azure App Service with HashiCorp Vault

This HashiCorp Terraform and Vault demo includes the following:
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

Notes:
* The Vault VM takes a few minutes to configure after provisioning has completed.
* The web app on Azure App Service takes a few minutes to spin up the first time you try to view it.
* Due to the way IP addresses are assigned in Azure, outputs will appear following the second terraform apply. Per https://www.terraform.io/docs/providers/azurerm/r/public_ip.html#ip_address
* If you'd like to access the Vault demo VM directly, the root token will be saved in the azureuser home folder of the Vault demo VM.

Troubleshooting:
* userdata install and configure script logs in /var/log/user-data.log
* Vault audit log in /var/log/vault_audit.log
* You can view the webapp logs using the Azure CLI with `az webapp log tail` after enabling [logging](https://docs.microsoft.com/en-us/azure/app-service/troubleshoot-diagnostic-logs).
