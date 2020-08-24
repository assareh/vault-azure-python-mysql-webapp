terraform {
  required_version = ">=0.12"

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "multicloud-provisioning-demo"
    workspaces {
      name = "vault-azure-python-mysql-webapp"
    }
  }
}
