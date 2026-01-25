terraform {

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57.0"
    }
  }

  # Uncomment and configure for remote state storage
   backend "azurerm" {
     resource_group_name  = "tfstate-rg"
     storage_account_name = "thirdrailtfstate"
     container_name       = "tfstate"
     key                  = "dev.thirdrail.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
