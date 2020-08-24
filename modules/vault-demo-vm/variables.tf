variable "client_id" {
}

variable "client_msi" {
}

variable "client_secret" {
}

variable "common_tags" {
  description = "common tags to apply to cloud resources"
  type        = map(string)
}

variable "license" {
}

variable "location" {
  description = "Azure location in which to create resources"
}

variable "prefix" {
  description = "Name prefix to add to the resources"
}

variable "public_key" {
}

variable "resource_group_name" {
}

variable "storage_uri" {
}

variable "subscription_id" {
}

variable "subnet_id" {
}

variable "tenant_id" {
}

variable "vault_namespace" {
}

variable "vm_size" {
}
