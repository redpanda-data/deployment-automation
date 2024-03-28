resource "aws_vpc" "test" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}

resource "aws_route53_zone" "test" {
  name = "devextest.local"
  vpc {
    vpc_id = aws_vpc.test.id
  }
  tags = var.tags
}

resource "aws_subnet" "server" {
  vpc_id     = aws_vpc.test.id
  cidr_block = "10.0.1.0/24"

  tags              = var.tags
  availability_zone = "us-west-2a"
}

resource "aws_subnet" "client" {
  vpc_id                  = aws_vpc.test.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true

  tags              = var.tags
  availability_zone = "us-west-2a"
}

resource "aws_internet_gateway" "test" {
  vpc_id = aws_vpc.test.id

  tags = var.tags
}

resource "aws_route_table" "test" {
  vpc_id = aws_vpc.test.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test.id
  }

  tags = var.tags
}

resource "aws_route_table_association" "client" {
  subnet_id      = aws_subnet.client.id
  route_table_id = aws_route_table.test.id
}

resource "aws_route_table_association" "server" {
  subnet_id      = aws_subnet.server.id
  route_table_id = aws_route_table.test.id
}

resource "aws_security_group" "client_sec_group" {
  name        = "${var.deployment_prefix}-client-sg"
  description = "client security group"
  tags        = var.tags
  vpc_id      = aws_vpc.test.id
  ingress {
    description = "Allow inbound to ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow inbound to proxy"
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "10.0.1.0/24", "10.0.2.0/24"]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id          = aws_vpc.test.id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.test.id]
  policy          = <<POLICY
{
  "Statement": [{
    "Action": "s3:*",
    "Effect": "Allow",
    "Resource": "*",
    "Principal": "*"
  }]
}
POLICY
}


module "redpanda-cluster" {
  source                          = "redpanda-data/redpanda-cluster/aws"
  version                         = "~> 1.0.0"
  public_key_path                 = var.public_key_path
  broker_count                    = var.broker_count
  deployment_prefix               = var.deployment_prefix
  enable_monitoring               = var.enable_monitoring
  tiered_storage_enabled          = var.tiered_storage_enabled
  allow_force_destroy             = var.allow_force_destroy
  vpc_id                          = aws_vpc.test.id
  distro                          = var.distro
  hosts_file                      = var.hosts_file
  tags                            = var.tags
  create_r53_records              = true
  associate_public_ip_addr_client = true
  security_groups_client          = [aws_security_group.client_sec_group.id]
  prefix_list_ids                 = [aws_vpc_endpoint.s3_endpoint.prefix_list_id]
  subnets                         = {
    broker = {
      "us-west-2a" = aws_subnet.server.id
    }
    client = {
      "us-west-2a" = aws_subnet.client.id
    }
  }
  zone_id           = aws_route53_zone.test.id
  client_count      = 1
  availability_zone = ["us-west-2a"]
  egress_rules      = {
    "PROXY" = {
      description     = "Allow Proxy"
      from_port       = 3128
      to_port         = 3128
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "INTERNAL" = {
      description     = "Allow intra group traffic"
      from_port       = 0
      to_port         = 0
      protocol        = -1
      enabled         = true
      cidr_blocks     = null
      self            = true
      security_groups = []
    }
  }
  ingress_rules = {
    "PROXY" = {
      description     = "Allow Proxy"
      from_port       = 3128
      to_port         = 3128
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "HTTP" = {
      description     = "Allow inbound to 80"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "HTTPS" = {
      description     = "Allow inbound to 443"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "SSH" = {
      description     = "Allow inbound to ssh"
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "Kafka" = {
      description     = "Allow inbound to access the Redpanda Kafka endpoint"
      from_port       = 9092
      to_port         = 9092
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "RPC" = {
      description     = "Allow security-group only to access Redpanda RPC endpoint for intra-cluster communication"
      from_port       = 33145
      to_port         = 33145
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "Admin" = {
      description     = "Allow anywhere inbound to access Redpanda Admin endpoint"
      from_port       = 9644
      to_port         = 9644
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "Grafana" = {
      description     = "Allow anywhere inbound to access grafana end point for monitoring"
      from_port       = 3000
      to_port         = 3000
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "JavaOMB" = {
      description     = "Allow inbound to access for Open Messaging Benchmark"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "Prometheus" = {
      description     = "Allow inbound to access Prometheus end point for monitoring"
      from_port       = 9090
      to_port         = 9090
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "NodeExporter" = {
      description     = "node_exporter access within the security-group for ansible"
      from_port       = 9100
      to_port         = 9100
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "SchemaRegistry" = {
      description     = "schema_registry access"
      from_port       = 8081
      to_port         = 8081
      protocol        = "tcp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "PING" = {
      description     = "Allow ICMP"
      from_port       = -1
      to_port         = -1
      protocol        = "icmp"
      enabled         = true
      cidr_blocks     = [aws_subnet.client.cidr_block]
      self            = null
      security_groups = [aws_security_group.client_sec_group.id]
    }
    "INTERNAL" = {
      description     = "Allow intra group traffic"
      from_port       = 0
      to_port         = 0
      protocol        = -1
      enabled         = true
      cidr_blocks     = null
      self            = true
      security_groups = []
    }
  }
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
  default = "rp-vpc"
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

variable "region" {
  type    = string
  default = "us-west-2"
}

provider "aws" {
  region = var.region
}

variable "vpc_id" {
  default = ""
  type    = string
}
