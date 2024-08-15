terraform {
  backend "azurerm" {
    resource_group_name  = "my-new-rg-02"
    storage_account_name = "mynewtf01"
    container_name       = "terraform"
    key                  = "terraform.tfstate"
  }
}