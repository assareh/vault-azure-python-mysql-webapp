This HashiCorp Terraform and Vault demo includes the following:
1. A Python webapp
2. A MySQL container used by the webapp (running on the Vault demo VM)
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
* Due to the way IP addresses are assigned in Azure, outputs will appear following the second terraform apply. Per https://www.terraform.io/docs/providers/azurerm/r/public_ip.html#ip_address
* If you'd like to access the Vault demo VM directly, the root token will be saved in the azureuser home folder of the Vault demo VM.