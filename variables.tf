variable "environment_name" {
  description = "Which environment this deployment is: 'dev' or 'prod'."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment_name)
    error_message = "environment_name must be 'dev' or 'prod'."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westus2"
}

variable "acr_name" {
  description = "Name of the shared registry (managed in shared/)."
  type        = string
  default     = "acrcontainerdemomolly"
}

variable "container_image" {
  description = "Full image reference. Supplied by the pipeline as the SHA-tagged build."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "min_replicas" {
  description = "Minimum replicas. 0 = scale to zero (dev); 1 = always warm (prod)."
  type        = number
}

variable "max_replicas" {
  description = "Maximum replicas."
  type        = number
  default     = 2
}

variable "container_cpu" {
  description = "vCPU per replica."
  type        = number
  default     = 0.25
}

variable "container_memory" {
  description = "Memory per replica."
  type        = string
  default     = "0.5Gi"
}

variable "kv_name_prefix" {
  description = "Key Vault name prefix; environment_name is appended. GLOBALLY unique, 3-24 chars total, alphanumeric and hyphens."
  type        = string
  default     = "kv-cdemo-molly-" # becomes kv-cdemo-molly-dev / -prod
}

variable "storage_name_prefix" {
  description = "Storage account name prefix; environment_name is appended. GLOBALLY unique, 3-24 chars total, lowercase alphanumeric ONLY (no hyphens)."
  type        = string
  default     = "stcdemomolly" # becomes stcdemomollydev / stcdemomollyprod
}
