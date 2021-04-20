# Vault Azure Auth Method Demo

In this document, I have written the steps for setting up the `azure` auth method in HashiCorp Vault. This repository also includes Terraform code that will provision a Vault server VM and a vault client VM. To use this repository, please follow steps 1-7 below.

## Setup and Configuration
### Azure Configuration
We need to create a role in our Azure account for Vault to use in order to verify Azure VM identities. We'll also be generating a service principal that will be provided to the Vault server.

**NOTE**: The following steps require that you have [jq](https://stedolan.github.io/jq/) and [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed, as well as are [logged in](https://docs.microsoft.com/en-us/cli/azure/authenticate-azure-cli) to your Azure subscription.

1. Let's define an environment variable to facilitate our task.
```
export ROLE_NAME_SUFFIX="<enter a value here to be used to identify the role in azure e.g. your name, the project name, or the app name>"
```

2. Determine your Azure Subscription ID:
```
ARM_SUBSCRIPTION_ID=$(az account show | jq -r .id)
```
**NOTE**: If you have multiple subscriptions you may need to identify the correct one and set this variable manually.

3. Create an Azure role with minimal permissions for Vault to use:
```
az role definition create --role-definition '{ "Name": "Vault Auth - ReadOnly - '$ROLE_NAME_SUFFIX'", "Description": "Access VM information to authenticate VMs with vault.", "Actions": [ "Microsoft.Compute/virtualMachines/*/read", "Microsoft.Compute/virtualMachineScaleSets/*/read"], "AssignableScopes": ["/subscriptions/'$ARM_SUBSCRIPTION_ID'"]}'
```

We've given Vault read only access to VM and VMSS scopes in a specific subscription.

4. Generate an Azure Service Principal against that role for Vault to use:
```
VAULT_AZURE_CREDS=$(az ad sp create-for-rbac -n "Vault-Azure-Auth-$ROLE_NAME_SUFFIX" \
  --role "Vault Auth - ReadOnly - $ROLE_NAME_SUFFIX" \
  --years 1 \
  --scopes /subscriptions/$ARM_SUBSCRIPTION_ID)
echo "${VAULT_AZURE_CREDS}"
```

You should see something like this:
```
{
  "appId": "28372dcc-acc7-32cs-9a84-7asdfasdfdf3",
  "displayName": "Vault-Azure-Auth-andy-test",
  "name": "http://Vault-Azure-Auth-andy-test",
  "password": "hvRMg4GEasdfaadfasdfasdvcaga-H_KRc",
  "tenant": "0e3e2e88-8caf-41ca-b4da-asdfasdf32ad"
}
```
**NOTE**: `password` is a secret. Guard it accordingly.

5. Lastly, let's save these as environment variables to make subsequent steps easier.
```
export ARM_TENANT_ID=$(echo $VAULT_AZURE_CREDS | jq -r .tenant)
export ARM_CLIENT_ID=$(echo $VAULT_AZURE_CREDS | jq -r .appId)
export ARM_CLIENT_SECRET=$(echo $VAULT_AZURE_CREDS | jq -r .password)
```

Great, now we're ready to build and run the demo!

### Provision with Terraform
6. Please modify the included `terraform.tfvars.example` file and provide the required values, then rename it to end with a .tfvars extension.

* `public_key` is your SSH public key so that you can SSH into the Azure VMs
* `subscription_id` is ARM_SUBSCRIPTION_ID from above
* `tenant_id` is ARM_TENANT_ID from above
* `client_id` is appId or ARM_CLIENT_ID from your service principal for provisioning with terraform
* `client_secret` is password or ARM_CLIENT_SECRET from your service principal for provisioning with terraform
* `vault_client_id` is ARM_CLIENT_ID from above
* `vault_client_secret` is ARM_CLIENT_SECRET from above

7. Please run `terraform init; terraform apply` and if it looks good, go ahead and type yes and press the enter key to apply it.

Once initial provisioning is complete (~10 mins), you should see something like this:
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

vault_addr = "http://20.69.153.79:8200"
vault_ip = "20.69.153.79"
vault_private_ip = "10.0.1.5"
vault_ssh = <<EOT

    Connect to your Vault server virtual machine via SSH:

    $ ssh azureuser@20.69.153.79

EOT
webapp_ip = "20.69.153.133"
webapp_ssh = <<EOT

    Connect to your webapp virtual machine via SSH:

    $ ssh azureuser@20.69.153.133

EOT
```

### Test it
Now let's test it.

**NOTE**: It may take up to 5 minutes after terraform provisioning completes for the instances to finish their userdata scripts and Vault to be ready.

8. SSH into the webapp virtual machine using the value of the `webapp_ssh` output from the previous step. In this command we'll gather an access token and other instance details from the metadata service, then pass to Vault in an authentication request. For the Vault server address please use the value of the `vault_private_ip` output from the previous step:
```
vault write \
      -address=http://10.0.1.4:8200 \
      auth/azure/login \
      role=dev-role \
      jwt=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -H Metadata:true | jq -r '.access_token') \
      subscription_id=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-08-01" | jq -r '.compute | .subscriptionId') \
      resource_group_name=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-08-01" | jq -r '.compute | .resourceGroupName') \
      vm_name=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2017-08-01" | jq -r '.compute | .name')
```

You should see something like this:
```
Key                               Value
---                               -----
token                             s.7zo8oW1jfEpmnJVGJ7MbeR29
token_accessor                    WT9GHwhyCKvLP5Va0GZG0Pso
token_duration                    768h
token_renewable                   true
token_policies                    ["default" "webapp"]
identity_policies                 []
policies                          ["default" "webapp"]
token_meta_resource_group_name    andy-webapp-rg
token_meta_role                   dev-role
token_meta_subscription_id        14692f20-9428-451b-8298-102ed4e39c2a
token_meta_vm_name                andy-webapp-webapp-vm
```

That's it! Vault has authenticated the VM based on its Azure identity and issued the VM a Vault token.

## Reference
**NOTE**: The following steps will be automatically performed by scripts when you provision this with terraform. They are documented here for reference.

### Vault Configuration
We need to enable and configure the `azure` auth method in Vault. We'll also be creating a role in Vault for our VMs to use.

**NOTE**: The following steps require that you have `vault` in your path, as well as that you are authenticated to Vault with sufficient privileges to perform these operations.

Enable Azure authentication in Vault:
```
vault auth enable azure
```

Configure the Azure auth method:\
_NOTE: The resource parameter **must** include the trailing slash._\
_NOTE: You may change the resource parameter, however the same address must be used in both the auth method configuration and the JWT from Azure._
```
vault write auth/azure/config \
      tenant_id=$ARM_TENANT_ID \
      resource=https://management.azure.com/ \
      client_id=$ARM_CLIENT_ID \
      client_secret=$ARM_CLIENT_SECRET
```

Create a role:
```
vault write auth/azure/role/dev-role \
      bound_subscription_ids=$ARM_SUBSCRIPTION_ID \
      policies=webapp
```

## Documentation
- https://www.vaultproject.io/docs/auth/azure
- https://www.vaultproject.io/api/auth/azure
- https://github.com/stenio123/azure-vault-terraform/tree/master/Azure-Auth-Method
- https://github.com/hashicorp/vault-plugin-auth-azure/issues/9
- https://github.com/hashicorp/vault-plugin-auth-azure/issues/17