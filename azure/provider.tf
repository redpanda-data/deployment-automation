terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.83.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.1.0"
    }
  }
}

provider "azurerm" {
  features {}
}