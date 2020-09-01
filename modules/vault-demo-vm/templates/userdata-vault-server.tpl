#!/usr/bin/env bash
set -x
exec > >(tee /var/log/user-data.log|logger -t user-data ) 2>&1

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT $0: $1"
}

logger "Running"

##--------------------------------------------------------------------
## Variables

# Detect package management system.
YUM=$(which yum 2>/dev/null)
APT_GET=$(which apt-get 2>/dev/null)

##--------------------------------------------------------------------
## Functions

user_rhel() {
  # RHEL/CentOS user setup
  sudo /usr/sbin/groupadd --force --system $${USER_GROUP}

  if ! getent passwd $${USER_NAME} >/dev/null ; then
    sudo /usr/sbin/adduser \
      --system \
      --gid $${USER_GROUP} \
      --home $${USER_HOME} \
      --no-create-home \
      --comment "$${USER_COMMENT}" \
      --shell /bin/false \
      $${USER_NAME}  >/dev/null
  fi
}

user_ubuntu() {
  # UBUNTU user setup
  if ! getent group $${USER_GROUP} >/dev/null
  then
    sudo addgroup --system $${USER_GROUP} >/dev/null
  fi

  if ! getent passwd $${USER_NAME} >/dev/null
  then
    sudo adduser \
      --system \
      --disabled-login \
      --ingroup $${USER_GROUP} \
      --home $${USER_HOME} \
      --no-create-home \
      --gecos "$${USER_COMMENT}" \
      --shell /bin/false \
      $${USER_NAME}  >/dev/null
  fi
}

##--------------------------------------------------------------------
## Install Base Prerequisites

logger "Setting timezone to UTC"
sudo timedatectl set-timezone UTC

if [[ ! -z $${YUM} ]]; then
  logger "RHEL/CentOS system detected"
  logger "Performing updates and installing prerequisites"
  sudo yum-config-manager --enable rhui-REGION-rhel-server-releases-optional
  sudo yum-config-manager --enable rhui-REGION-rhel-server-supplementary
  sudo yum-config-manager --enable rhui-REGION-rhel-server-extras
  sudo yum -y check-update
  sudo yum install -q -y wget unzip bind-utils ruby rubygems ntp jq docker.io
  sudo systemctl start ntpd.service
  sudo systemctl enable ntpd.service
elif [[ ! -z $${APT_GET} ]]; then
  logger "Debian/Ubuntu system detected"
  logger "Performing updates and installing prerequisites"
  sudo apt-get -qq -y update
  sudo apt-get install -qq -y wget unzip dnsutils ruby rubygems ntp jq docker.io
  sudo systemctl start ntp.service
  sudo systemctl enable ntp.service
  logger "Disable reverse dns lookup in SSH"
  sudo sh -c 'echo "\nUseDNS no" >> /etc/ssh/sshd_config'
  sudo service ssh restart
else
  logger "Prerequisites not installed due to OS detection failure"
  exit 1;
fi


##--------------------------------------------------------------------
## Install MySQL
docker pull mysql/mysql-server:5.7.21
mkdir ~/mysql
docker run --name mysql \
  -p 3306:3306 \
  -v ~/mysql:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_ROOT_HOST=% \
  -e MYSQL_DATABASE=my_app \
  -d mysql/mysql-server:5.7.21


##--------------------------------------------------------------------
## Configure Vault user

USER_NAME="vault"
USER_COMMENT="HashiCorp Vault user"
USER_GROUP="vault"
USER_HOME="/srv/vault"

if [[ ! -z $${YUM} ]]; then
  logger "Setting up user $${USER_NAME} for RHEL/CentOS"
  user_rhel
elif [[ ! -z $${APT_GET} ]]; then
  logger "Setting up user $${USER_NAME} for Debian/Ubuntu"
  user_ubuntu
else
  logger "$${USER_NAME} user not created due to OS detection failure"
  exit 1;
fi

##--------------------------------------------------------------------
## Install Vault

logger "Installing Vault"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install -y vault-enterprise

logger "/usr/bin/vault --version: $(/usr/bin/vault --version)"

logger "Configuring Vault"

sudo tee /etc/vault.d/vault.hcl <<EOF
# Full configuration options can be found at https://www.vaultproject.io/docs/configuration

ui=true

disable_mlock = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address                  = "0.0.0.0:8200"
  tls_cert_file            = "/opt/vault/tls/tls.crt"
  tls_key_file             = "/opt/vault/tls/tls.key"
  tls_disable_client_certs = "true"
}

seal "azurekeyvault" {
  client_id      = "${client_id}"
  client_secret  = "${client_secret}"
  tenant_id      = "${tenant_id}"
  vault_name     = "${vault_name}"
  key_name       = "${key_name}"
}
EOF

sudo chown -R vault:vault /etc/vault.d /etc/ssl/vault
sudo chmod -R 0644 /etc/vault.d/*

sudo tee -a /etc/environment <<EOF
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
EOF

source /etc/environment

logger "Granting mlock syscall to vault binary"
sudo setcap cap_ipc_lock=+ep /usr/bin/vault

##--------------------------------------------------------------------
## Install Vault Systemd Service

read -d '' VAULT_SERVICE <<EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

##--------------------------------------------------------------------
## Install Vault Systemd Service that allows additional params/args

sudo tee /etc/systemd/system/vault@.service > /dev/null <<EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Environment="OPTIONS=%i"
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl \$OPTIONS
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF


if [[ ! -z $${YUM} ]]; then
  SYSTEMD_DIR="/etc/systemd/system"
  logger "Installing systemd services for RHEL/CentOS"
  echo "$${VAULT_SERVICE}" | sudo tee $${SYSTEMD_DIR}/vault.service
  sudo chmod 0664 $${SYSTEMD_DIR}/vault*
elif [[ ! -z $${APT_GET} ]]; then
  SYSTEMD_DIR="/lib/systemd/system"
  logger "Installing systemd services for Debian/Ubuntu"
  echo "$${VAULT_SERVICE}" | sudo tee $${SYSTEMD_DIR}/vault.service
  sudo chmod 0664 $${SYSTEMD_DIR}/vault*
else
  logger "Service not installed due to OS detection failure"
  exit 1;
fi

sudo systemctl enable vault
sudo systemctl start vault

##-------------------------------------------------------------------
#write out current crontab
crontab -l > mycron
#echo new cron into cron file
echo "00 * * * * systemctl restart vault" >> mycron
echo "30 * * * * systemctl restart vault" >> mycron
#install new cron file
crontab mycron
rm mycron

sleep 15
logger "Initializing Vault and storing results for azureuser user"
vault operator init -recovery-shares 1 -recovery-threshold 1 -format=json > /tmp/key.json
sudo chown azureuser:azureuser /tmp/key.json

logger "Saving root_token and recovery key to azureuser user's home"
VAULT_TOKEN=$(cat /tmp/key.json | jq -r ".root_token")
echo $VAULT_TOKEN > /home/azureuser/root_token
sudo chown azureuser:azureuser /home/azureuser/root_token
echo $VAULT_TOKEN > /home/azureuser/.vault-token
sudo chown azureuser:azureuser /home/azureuser/.vault-token

echo $(cat /tmp/key.json | jq -r ".recovery_keys_b64[]") > /home/azureuser/recovery_key
sudo chown azureuser:azureuser /home/azureuser/recovery_key

cat << EOF > /etc/vault.d/vaultrc
#!/bin/bash
export VAULT_ROOT_TOKEN=$VAULT_TOKEN
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
EOF

logger "Setting VAULT_ADDR and VAULT_TOKEN"
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_TOKEN=$VAULT_TOKEN

logger "Waiting for Vault to finish preparations (10s)"
sleep 10

logger "Creating policies"
sudo cat << 'EOF' > /tmp/webapppolicy.hcl
path "data_protection/database/creds/vault-demo-app-long" {
    capabilities = ["read"]
}

path "data_protection/database/creds/vault-demo-app" {
    capabilities = ["read"]
}

path "data_protection/transit/encrypt/customer-key" {
    capabilities = ["create", "read", "update"]
}

path "data_protection/transit/decrypt/customer-key" {
    capabilities = ["create", "read", "update"]
}

path "data_protection/transform/encode/ssn" {
    capabilities = ["create", "read", "update"]
}

path "data_protection/transform/decode/ssn" {
    capabilities = ["create", "read", "update"]
}

path "data_protection/masking/transform/encode/ccn" {
    capabilities = ["create", "read", "update"]
}
EOF

# # not using sentinel now, replaced with bound CIDR on dev-role
# sudo cat << 'EOF' > /tmp/cidr-policy.sentinel
# import "sockaddr"

# cidrcheck = rule {
#     sockaddr.is_contained(request.connection.remote_addr, "10.0.2.254/32")
# }

# main = rule {
#     cidrcheck
# }
# EOF

# POLICY=$(base64 /tmp/cidr-policy.sentinel)

logger "Configuring auth methods and secrets engines"
set -v
export VAULT_SKIP_VERIFY=true

touch /var/log/vault_audit.log
chown vault:vault /var/log/vault_audit.log
vault audit enable file file_path=/var/log/vault_audit.log

vault write sys/license text="${license}"

vault namespace create ${vault_namespace}
export VAULT_NAMESPACE=${vault_namespace}
vault policy write webapp /tmp/webapppolicy.hcl

vault auth enable jwt

vault write auth/jwt/config \
            oidc_discovery_url=https://sts.windows.net/${tenant_id}/ \
            bound_issuer=https://sts.windows.net/${tenant_id}/

cat <<EOF >payload.json
{
  "bound_audiences": "https://management.azure.com/",
  "bound_claims": {
    "idp": "https://sts.windows.net/${tenant_id}/",
    "oid": "${client_msi}",
    "tid": "${tenant_id}"
  },
  "bound_subject": "${client_msi}",
  "claim_mappings": {
    "appid": "application_id",
    "xms_mirid": "resource_id"
  },
  "policies": ["webapp"],
  "role_type": "jwt",
  "token_bound_cidrs": ["10.0.2.254/32"],
  "token_ttl": "24h",
  "user_claim": "sub"
}
EOF

curl \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    --header "X-Vault-Namespace: $VAULT_NAMESPACE" \
    --insecure \
    --request POST \
    --data @payload.json \
    $VAULT_ADDR/v1/auth/jwt/role/webapp-role

# # not using this any more, replaced with above
# vault write auth/jwt/role/webapp-role \
#       policies=webapp \
#       bound_audiences=https://management.azure.com/ \
#       user_claim=sub \
#       role_type=jwt \
#       token_max_ttl=24h \
#       bound_subject=${client_msi}

vault auth enable azure

vault write auth/azure/config tenant_id="${tenant_id}" resource="https://management.azure.com/" client_id="${client_id}" client_secret="${client_secret}"

vault write auth/azure/role/dev-role policies="webapp" bound_subscription_ids="${subscription_id}" bound_resource_groups="${resource_group_name}"

vault secrets enable -path=data_protection/database database

# Configure the database secrets engine to talk to MySQL
vault write data_protection/database/config/wsmysqldatabase \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(127.0.0.1:3306)/" \
    allowed_roles="vault-demo-app","vault-demo-app-long" \
    username="root" \
    password="root"

# Rotate root password
#vault write  -force data_protection/database/rotate-root/wsmysqldatabase

# Create a role with a longer TTL
vault write data_protection/database/roles/vault-demo-app-long \
    db_name=wsmysqldatabase \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT ALL ON my_app.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# Create a role with a shorter TTL
vault write data_protection/database/roles/vault-demo-app \
    db_name=wsmysqldatabase \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT ALL ON my_app.* TO '{{name}}'@'%';" \
    default_ttl="3m" \
    max_ttl="6m"

#test and generate dynamic username password
vault read data_protection/database/creds/vault-demo-app-long

logger "Database secret engine with mysql plugin configured "

logger "Enabling the vault transit secrets engine..."

# Enable the transit secret engine
vault secrets enable  -path=data_protection/transit transit

# Create our customer key
vault write  -f data_protection/transit/keys/customer-key

# Create our archive key to demonstrate multiple keys
vault write -f data_protection/transit/keys/archive-key

#test and see if encryption works
vault write data_protection/transit/encrypt/customer-key plaintext=$(base64 <<< "my secret data")

vault write data_protection/transit/encrypt/archive-key plaintext=$(base64 <<< "my secret data")

logger "Transit secret engine is setup"
#enable the transform secret engine
vault secrets enable  -path=data_protection/transform transform

#Define a role ssn with transformation ssn
vault write data_protection/transform/role/ssn transformations=ssn

#create a transformation of type fpe using built in template for social security number and assign role ssn to it that we created earlier
vault write data_protection/transform/transformation/ssn type=fpe template=builtin/socialsecuritynumber tweak_source=internal allowed_roles=ssn
#test if the transformation was created successfully
vault list data_protection/transform/transformation
vault read  data_protection/transform/transformation/ssn
#test if you are able to transform a SSN
vault write data_protection/transform/encode/ssn value=111-22-3333

#enable the transform secret engine for masking
vault secrets enable  -path=data_protection/masking/transform transform

#Define a role ccn with transformation ccn
vault write data_protection/masking/transform/role/ccn transformations=ccn

#create a transformation of type masking using a template defined in next step and assign role ccn to it that we created earlier
vault write data_protection/masking/transform/transformation/ccn \
        type=masking \
        template="card-mask" \
        masking_character="#" \
        allowed_roles=ccn
#create the template for masking
vault write data_protection/masking/transform/template/card-mask type=regex \
        pattern="(\d{4})-(\d{4})-(\d{4})-\d{4}" \
        alphabet="builtin/numeric"
#test if the masking transformation was created successfully
vault list data_protection/masking/transform/transformation
vault read  data_protection/masking/transform/transformation/ccn
#test if you are able to mask a Credit Card number
vault write data_protection/masking/transform/encode/ccn value=1111-2211-3333-1111

# # apply egp sentinel policy
# vault write sys/policies/egp/cidr-policy \
#         policy="$POLICY" \
#         paths="data_protection/*" \
#         enforcement_level="hard-mandatory"

# test azure auth - this will work
vault write auth/azure/login role="dev-role" \
  jwt="$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F'  -H Metadata:true -s | jq -r .access_token)" \
  subscription_id="${subscription_id}" \
  resource_group_name="${resource_group_name}" \
  vm_name="${vault_vm_name}"

# test jwt auth - this will fail
vault write auth/jwt/login role="webapp-role" \
  jwt="$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F'  -H Metadata:true -s | jq -r .access_token)" \

logger "azure auth should work, jwt auth should fail"
logger "Complete"
