terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # Use a 4.x version
    }
  }
}

provider "azurerm" {
  # This block is required for the AzureRM provider
  features {}
}

terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "ddgstatefileedgardl"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
    use_oidc             = true # Allows GitHub to use the OIDC trust
  }
}
