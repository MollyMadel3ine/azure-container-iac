variable "environment_name" {
  description = "Which environment this deployment is: 'dev' or 'prod'. Drives naming, tagging, and what /health reports. No default on purpose — every plan must state its environment."
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
  description = "Full image reference. Supplied by the pipeline as the SHA-tagged build on every run; for local applies, pass -var or set in the tfvars."
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
