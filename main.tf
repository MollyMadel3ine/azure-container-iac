# ------------------------------------------------------------------
# Root config: ONE environment definition, deployed per environment.
# Phase 4: zero secrets — a user-assigned managed identity handles
# ACR pulls, Key Vault reads, and blob storage access. No passwords,
# connection strings, or keys exist anywhere in this configuration.
#
# Why USER-assigned (not system-assigned): a system-assigned identity
# only exists after the app is created, but the app must pull its
# image WITH that identity during creation — circular. Creating the
# identity first breaks the loop.
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
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_container_registry" "shared" {
  name                = var.acr_name
  resource_group_name = "rg-container-shared"
}

data "azurerm_client_config" "current" {}

locals {
  tags = {
    project     = "container-app-iac"
    managed_by  = "terraform"
    environment = var.environment_name
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-container-demo-${var.environment_name}"
  location = var.location
  tags     = local.tags
}

# ---------------- The identity ----------------
# The app's face to the world: every Azure resource it touches, it
# touches as this identity, authorized by RBAC below.

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-container-demo-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

# ---------------- Key Vault + demo secret ----------------

resource "azurerm_key_vault" "this" {
  name                       = "${var.kv_name_prefix}${var.environment_name}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true # roles, not access policies — consistent with everything else
  purge_protection_enabled   = false
  tags                       = local.tags
}

# A benign demo secret the app reads at request time — proof of
# identity-based access with a visible payoff.
resource "azurerm_key_vault_secret" "demo" {
  name         = "demo-message"
  value        = "Hello from ${var.environment_name} Key Vault - no passwords were used"
  key_vault_id = azurerm_key_vault.this.id

  # The identity running terraform needs KV data-plane rights before
  # it can write the secret; see the Secrets Officer assignment below.
  depends_on = [azurerm_role_assignment.pipeline_kv_officer]
}

# ---------------- Storage ----------------

resource "azurerm_storage_account" "this" {
  name                            = "${var.storage_name_prefix}${var.environment_name}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false # RBAC-only: keys don't merely go unused — they don't work
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "visits" {
  name               = "visits"
  storage_account_id = azurerm_storage_account.this.id
}

# ---------------- RBAC: least privilege, per resource ----------------

# The app's identity may pull images...
resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# ...read secrets from THIS environment's vault...
resource "azurerm_role_assignment" "app_kv_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# ...and read/write blobs in THIS environment's storage. Nothing else.
resource "azurerm_role_assignment" "app_storage_blob" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# The pipeline SP needs data-plane rights on the vault to write the
# demo secret (management-plane Contributor isn't enough for RBAC vaults).
resource "azurerm_role_assignment" "pipeline_kv_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------- Container Apps ----------------

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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # Registry auth by identity — no username, no password, no secret block.
  registry {
    server   = data.azurerm_container_registry.shared.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  template {
    min_replicas = var.min_replicas
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

      env {
        name  = "KEY_VAULT_URI"
        value = azurerm_key_vault.this.vault_uri
      }

      env {
        name  = "STORAGE_ACCOUNT_URL"
        value = azurerm_storage_account.this.primary_blob_endpoint
      }

      # Which identity DefaultAzureCredential should use (an app can
      # wear several user-assigned identities).
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.app.client_id
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

  # Pull happens at creation — the role must exist first.
  depends_on = [azurerm_role_assignment.app_acr_pull]
}
