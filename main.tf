# ------------------------------------------------------------------
# Root config: ONE definition, deployed per environment.
#
# Which environment this manages is decided at init/plan time, not
# in code:
#   terraform init -backend-config="key=container-app-dev.tfstate"
#   terraform plan -var-file=dev.tfvars
# Swap dev→prod in both and the same code manages prod, in a fully
# separate state. A botched dev apply cannot touch prod — prod isn't
# in the state being written.
#
# The ACR lives in shared/ (its own state); this config finds it by
# name via a data source.
# ------------------------------------------------------------------

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Partial backend: everything except the key, which is supplied per
  # environment at init time (-backend-config).
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatemolly" # ← your state account
    container_name       = "tfstate"
  }
}

provider "azurerm" {
  features {}
}

# The shared registry, by reference — not managed here.
data "azurerm_container_registry" "shared" {
  name                = var.acr_name
  resource_group_name = "rg-container-shared"
}

resource "azurerm_resource_group" "main" {
  name     = "rg-container-demo-${var.environment_name}"
  location = var.location
  tags     = local.tags
}

locals {
  tags = {
    project     = "container-app-iac"
    managed_by  = "terraform"
    environment = var.environment_name
  }
}

resource "azurerm_container_app_environment" "this" {
  name                = "container-demo-${var.environment_name}-cae"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_container_app" "this" {
  name                         = "container-demo-${var.environment_name}-app"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.tags

  registry {
    server               = data.azurerm_container_registry.shared.login_server
    username             = data.azurerm_container_registry.shared.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = data.azurerm_container_registry.shared.admin_password
  }

  template {
    min_replicas = var.min_replicas # the dev/prod difference, as data
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "APP_ENVIRONMENT"
        value = var.environment_name
      }

      env {
        name  = "IMAGE_TAG"
        value = var.container_image
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
