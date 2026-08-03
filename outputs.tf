output "app_url" {
  description = "Public URL of the container app."
  value       = "https://${azurerm_container_app.this.ingress[0].fqdn}"
}

output "acr_login_server" {
  description = "Registry address for docker tag/push (e.g. acrcontainerdemomolly.azurecr.io)."
  value       = azurerm_container_registry.this.login_server
}

output "acr_name" {
  description = "Registry name for az acr login."
  value       = azurerm_container_registry.this.name
}
