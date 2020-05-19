################################################################################
terraform {
  required_version  = ">= 0.12.23"
}

################################################################################
# providers
provider vault {
  address = var.vault_addr
  auth_login {
    path            = var.vault_auth_path

    parameters      = {
      role_id       = var.vault_role_id
      secret_id     = var.vault_secret_id
    }
  }
}

provider "aws" {
  region = var.aws_region
}

################################################################################
# retrieve secrets from Vault
data vault_generic_secret api_token {
  path = var.vault_secret_path
}

################################################################################
# AWS

# VPC
data "aws_vpc" "vpc" {
  id = var.vpc_id
}

# Security Groups
resource "aws_security_group" "demo-sg" {
  name          = "${var.owner}-demo-sg"
  description   = "Allow all traffic from owner ip"
  vpc_id        = data.aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.owner_ip]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Owner = var.owner
  }
}

# Latest Ubuntu 18.04 image
data aws_ami ubuntu {
  most_recent            = true

  filter {
    name                 = "name"
    values               = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name                 = "virtualization-type"
    values               = ["hvm"]
  }

  # Canonical
  owners                 = ["099720109477"]
}

# instance user data
data template_file user_data {
  template               = file("userdata.tpl")

  vars = {
    app_path             = "/opt/app1"
    api_token            = data.vault_generic_secret.api_token.data[var.vault_secret_key]
  }
}

# aws instance
resource aws_instance ubuntu {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.ssh_key_name
  user_data              = data.template_file.user_data.rendered
  vpc_security_group_ids = [aws_security_group.demo-sg.id]

  tags = {
    Owner                = var.owner
    Name                 = var.name
    TTL                  = var.ttl
  }
}
