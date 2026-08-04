variable "project_name" {
  description = "Short prefix for resource names."
  type        = string
  default     = "container-demo"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westus2"
}

variable "acr_name" {
  description = "Container registry name: GLOBALLY unique, 5-50 chars, alphanumeric only (no hyphens!)."
  type        = string
  default     = "acrcontainerdemomolly"
}

variable "container_image" {
  description = <<-EOT
    Full image reference the app runs. Defaults to Microsoft's public
    quickstart image so the FIRST apply succeeds before your own image
    exists in ACR (solves the registry/app chicken-and-egg). After
    pushing your image, re-apply with this set to
    <acr>.azurecr.io/container-demo:v1 (or use a tfvars).
    NOTE: the quickstart image listens on port 80 — the ingress
    target_port of 8000 is correct for YOUR image; the quickstart will
    show as unhealthy until your image replaces it. That's expected.

    LIFECYCLE NOTE: passing this via -var does not persist — a plain
    `terraform apply` reverts to the default. Interim fix: pin the
    current image in terraform.tfvars. Permanent fix: Phase 2's
    pipeline passes the SHA tag on every run, making this a per-deploy
    parameter rather than stored configuration.
  EOT
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "environment_name" {
  description = "Environment label the app reports at /health. Becomes load-bearing in Phase 3."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags for all resources."
  type        = map(string)
  default = {
    project    = "container-app-iac"
    managed_by = "terraform"
  }
}
