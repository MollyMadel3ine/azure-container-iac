# ------------------------------------------------------------------
# Phase 1: registry + Container Apps environment + one container app.
#
# Deliberately a flat configuration (no modules yet): three resources
# don't earn module ceremony. Phase 3 restructures for multi-env,
# and that's when parameterization gets real. Documented trade-off.
# ------------------------------------------------------------------

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Same state storage account as project #1 — one bootstrap, many
  # projects. Only the key differs.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatemolly" # ← your actual account name
    container_name       = "tfstate"
    key                  = "container-app.tfstate"
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "rg-container-demo"
  location = var.location
  tags     = var.tags
}

# ---------------- Container registry ----------------
# admin_enabled is the Phase 1 shortcut: username/password auth for
# both the container app's pulls and your local docker push. Phase 4
# replaces this with managed identity and turns it off — the README
# tracks that as a known, deliberate stepping stone.

resource "azurerm_container_registry" "this" {
  name                = var.acr_name # globally unique, alphanumeric ONLY
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = var.tags
}

# ---------------- Container Apps environment ----------------
# The "cluster" the apps run in. No Log Analytics wired yet — Phase 5.

resource "azurerm_container_app_environment" "this" {
  name                = "${var.project_name}-cae"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# ---------------- The container app ----------------

resource "azurerm_container_app" "this" {
  name                         = "${var.project_name}-app"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = var.tags

  # Registry credentials: ACR admin user, password held as a Container
  # Apps secret (referenced by name, never inline).
  registry {
    server               = azurerm_container_registry.this.login_server
    username             = azurerm_container_registry.this.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.this.admin_password
  }

  template {
    min_replicas = 0 # scale to zero — the ~$0 idle story
    max_replicas = 2

    container {
      name   = "app"
      image  = var.container_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "APP_ENVIRONMENT"
        value = var.environment_name
      }

      env {
        name  = "IMAGE_TAG"
        value = var.container_image # full ref for now; SHA tags in Phase 2
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
