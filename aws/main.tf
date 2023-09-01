resource "aws_vpc" "test" {
  count = var.subnet_id == "" ? 1 : 0  # Only create if subnet_id is empty

  cidr_block = "10.0.0.0/16"
  tags       = var.tags
}

resource "aws_subnet" "server" {
  count = var.subnet_id == "" ? 1 : 0  # Only create if subnet_id is empty

  vpc_id     = aws_vpc.test[0].id
  cidr_block = "10.0.1.0/24"

  tags              = var.tags
  availability_zone = "us-west-2a"
}

resource "aws_internet_gateway" "test" {
  count = var.subnet_id == "" ? 1 : 0  # Only create if subnet_id is empty

  vpc_id = aws_vpc.test[0].id

  tags = var.tags
}

resource "aws_route_table" "test" {
  count  = var.subnet_id == "" ? 1 : 0  # Only create if subnet_id is empty
  vpc_id = aws_vpc.test[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test[0].id
  }

  tags = var.tags
}

resource "aws_route_table_association" "test" {
  count          = var.subnet_id == "" ? 1 : 0  # Only create if subnet_id is empty
  subnet_id      = aws_subnet.server[0].id
  route_table_id = aws_route_table.test[0].id
}

module "redpanda-cluster" {
  source                 = "redpanda-data/redpanda-cluster/aws"
  version                = "~> 1.0.0"
  public_key_path        = var.public_key_path
  broker_count           = var.broker_count
  enable_monitoring      = var.enable_monitoring
  tiered_storage_enabled = var.tiered_storage_enabled
  allow_force_destroy    = var.allow_force_destroy
  aws_region             = var.aws_region
  vpc_id                 = local.actual_vpc_id
  distro                 = var.distro
  hosts_file             = var.hosts_file
  tags                   = var.tags
  subnets                = {
    broker = {
      (var.availability_zone) = local.actual_subnet_id
    }
  }
  availability_zone        = [var.availability_zone]
  deployment_prefix        = var.deployment_prefix
  associate_public_ip_addr = var.associate_public_ip_addr
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "broker_count" {
  type    = number
  default = 3
}

variable "deployment_prefix" {
  type    = string
  default = "rp-public-vpc"
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "tiered_storage_enabled" {
  type    = bool
  default = false
}

variable "allow_force_destroy" {
  type    = bool
  default = false
}

variable "distro" {
  type    = string
  default = "ubuntu-focal"
}

variable "hosts_file" {
  type    = string
  default = "hosts.ini"
}

variable "tags" {
  type    = map(string)
  default = {}
}

terraform {
  required_version = ">=0.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

provider "aws" {
  region = var.aws_region
}

variable "availability_zone" {
  type    = string
  default = "us-west-2a"
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "vpc_id" {
  type    = string
  default = ""
}

locals {
  # If subnet_id is not empty, use it. Otherwise, use the id of the created subnet
  actual_subnet_id = var.subnet_id != "" ? var.subnet_id : aws_subnet.server[0].id
  actual_vpc_id    = var.vpc_id != "" ? var.vpc_id : aws_vpc.test[0].id
}

variable "associate_public_ip_addr" {
  default = true
  type    = bool
}
