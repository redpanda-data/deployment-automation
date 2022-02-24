terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.73.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
    time = {
      source = "hashicorp/time"
      version = "0.7.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

