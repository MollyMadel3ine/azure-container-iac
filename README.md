# Containerized App on Azure — Multi-Environment IaC

A containerized Python service on Azure Container Apps, promoted through dev and prod environments by a gated pipeline, authenticating to Azure resources with managed identity — no passwords anywhere. Built entirely through code.

This is a deliberate companion to [azure-webapp-iac](https://github.com/MollyMadel3ine/azure-webapp-iac): where that project demonstrated network security, private endpoints, and gated IaC delivery, this one covers containers, multi-environment Terraform structure, image-based CI/CD, and identity-based access.

**Status: Phase 1 in progress** — local container loop complete; Azure infrastructure next.

## Quick start (local)

```bash
docker build -t container-demo:local .
docker run --rm -p 8000:8000 container-demo:local
curl http://localhost:8000/health
```

The health endpoint reports environment, image tag, and container hostname — metadata that becomes the proof of environment separation in Phase 3.

## Roadmap

- [ ] **Phase 1 — Containerize + core infrastructure**: multi-stage Dockerfile (non-root, ~150MB), Azure Container Registry, Container Apps environment + app via Terraform, remote state
- [ ] **Phase 2 — CI/CD**: pipeline builds and pushes SHA-tagged images, terraform-applies the new tag, and smoke-tests its own deployment — app delivery and infrastructure in one gated flow
- [ ] **Phase 3 — Multi-environment promotion**: dev and prod from one configuration via tfvars and isolated state; merge → deploy dev → smoke test → manual gate → deploy prod
- [ ] **Phase 4 — Zero secrets**: system-assigned managed identity with least-privilege RBAC for storage and Key Vault access; no connection strings or passwords anywhere
- [ ] **Phase 5 (optional) — Observability**: Log Analytics, diagnostics, and an alert verified by fire drill, per the pattern established in project #1

Each phase lands as its own pull request. Full plan: [docs/project-plan.md](docs/project-plan.md)

## Cost

Container Apps scale to zero; ACR Basic is ~$5/month — the project idles at pocket change and can stay permanently deployed as a live demo.
