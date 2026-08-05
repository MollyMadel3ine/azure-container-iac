# ------------------------------------------------------------------
# shared/main.tf — infrastructure BOTH environments depend on.
#
# One registry, both environments pull the same SHA-tagged image:
# build once, promote the artifact, never rebuild for prod. This
# config has its own state (shared.tfstate) and changes rarely —
# applied manually (like a bootstrap), since the pipeline's job is
# promoting apps, not managing the registry they come from.
# ------------------------------------------------------------------

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatemolly" # ← your state account
    container_name       = "tfstate"
    key                  = "container-app-shared.tfstate"
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "shared" {
  name     = "rg-container-shared"
  location = "westus2"
  tags = {
    project    = "container-app-iac"
    managed_by = "terraform"
    scope      = "shared"
  }
}

# Admin credentials remain the Phase 1 shortcut — Phase 4 replaces
# them with managed identity and disables admin access.
resource "azurerm_container_registry" "this" {
  name                = "acrcontainerdemomolly" # ← your registry name
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = azurerm_resource_group.shared.tags
}

output "acr_id" {
  value = azurerm_container_registry.this.id
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}
