################################################################################
# Vault variables
variable vault_addr {
  type          = string
  description   = "Vault Cluster Address"
}

variable vault_role_id {
  type          = string
  description   = "Role ID for AppRole auth"
}

variable vault_secret_id {
  type          = string
  description   = "Secret ID for AppRole auth"
}

variable vault_auth_path {
  type          = string
  description   = "The login path of the auth backend."
  default       = "auth/approle/login"
}

variable vault_secret_path {
  type = string
  description = "Path in Vault from which to retrieve the API Token."
}

variable vault_secret_key {
  type = string
  default = "api_key"
  description = "Name of key that holds the API Token"
}

# AWS variables
variable aws_region {
  type        = string
  description = "AWS region"
  default     = "us-west-2"
}

variable vpc_id {
  type        = string
  description = "VPC ID"
}

variable subnet_id {
  type        = string
  description = "Subnet ID in which to deploy our hashistack instance."
}

variable instance_type {
  type        = string
  description = "type of EC2 instance to provision."
  default     = "t2.micro"
}

# tagging variables
variable name {
  type        = string
  description = "Name tag"
  default = "tfe-aws-demo"
}

variable owner {
  type        = string
  description = "Owner tag"
}

variable ttl {
  description = "value of ttl tag on EC2 instances"
  default     = "24"
}

# security group / access
variable owner_ip {
  type        = string
  description = "IP address of owner's home or office that will be allowed to access our hashistack instance."
}

variable ssh_key_name {
  type        = string
  description = "Name of existing SSH key."
}
