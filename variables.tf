variable "appservicedocker" {
  description = "The docker image to run as an app service"
  default     = "assareh/transit-app-example:latest"
}

variable "appserviceplantier" {
  description = "The tier of app service plan"
  default     = "S1/Standard"
}

variable "client_id" {
  description = "Azure Service Principal appId"
}

variable "client_secret" {
  description = "Azure Service Principal password"
}

variable "common_tags" {
  description = "Common tags to apply to cloud resources"
  type        = map(string)
  default = {
    Purpose = "Hashidemos"
  }
}

variable "license" {
  description = "(Optional) Vault Enterprise license, if you have one"
  default     = ""
}

variable "location" {
  description = "Azure location in which to create resources"
  default     = "West US 2"
}

variable "prefix" {
  description = "Name prefix to add to the resources"
  default     = "hashidemos"
}

variable "public_key" {
  description = "Your SSH public key (e.g. ssh-rsa ...)"
}

variable "subscription_id" {
  description = "Azure Service Principal subscription ID"
}

variable "tenant_id" {
  description = "Azure Service Principal tenant"
}

variable "vault_namespace" {
  description = "(Optional) Vault Namespace to use"
  default     = "root"
}

variable "vm_size" {
  description = "Azure VM size to provision"
  default     = "Standard_B2s"
}
