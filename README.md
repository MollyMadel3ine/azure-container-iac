# Containerized App on Azure — Multi-Environment IaC, Zero Secrets

A containerized Python service on Azure Container Apps, promoted through dev and prod environments by a gated pipeline, and authenticating to every Azure resource it touches — the container registry, Key Vault, and Blob Storage — as a **managed identity**. No passwords, keys, or connection strings exist anywhere in this system: not in code, not in configuration, not in Terraform state for the app's access, and not on the registry (admin credentials are disabled — they don't merely go unused, they don't exist).

A deliberate companion to [azure-webapp-iac](https://github.com/MollyMadel3ine/azure-webapp-iac): where that project's security boundary is the **network** (private endpoints, VNet-scoped DNS, no public data paths), this project's boundary is **identity** (RBAC-only access, short-lived tokens, nothing stealable). Together they cover the two dominant Azure security postures — and the trade-offs between them are documented, not hidden.

**Status: Phases 1–4 complete — Phase 5 (observability) in progress.**

**Live demo — the zero-secrets proof:** both environments run permanently. `/identity` reads a Key Vault secret and increments a Blob Storage counter, all as the managed identity:

![Identity-based access working in dev](images/identity-proof-dev.png)

And the negative proof — the registry refusing credential access, while both environments (which pull by identity) keep running:

![ACR admin credentials disabled](images/identity-acr-admin-disabled.png)

## Architecture

```mermaid
flowchart TB
    subgraph shared["Shared (own state)"]
        acr[("Container Registry<br/>admin DISABLED —<br/>identity pulls only")]
    end

    subgraph dev["Dev — its own state, identity, vault, storage"]
        devapp["Container App<br/>min 0 (scale to zero)"]
        devkv[("Key Vault")]
        devst[("Blob Storage<br/>shared keys disabled")]
    end

    subgraph prod["Prod — its own state, identity, vault, storage"]
        prodapp["Container App<br/>min 1 (always warm)"]
        prodkv[("Key Vault")]
        prodst[("Blob Storage<br/>shared keys disabled")]
    end

    acr -- "AcrPull (RBAC)" --> devapp
    acr -- "AcrPull (RBAC)" --> prodapp
    devapp -- "Secrets User" --> devkv
    devapp -- "Blob Contributor" --> devst
    prodapp -- "Secrets User" --> prodkv
    prodapp -- "Blob Contributor" --> prodst
```

Each environment owns its complete stack — identity, vault, storage, app — in an isolated state file. The only shared resource is the registry, because the promotion doctrine requires both environments to pull the *same* SHA-tagged artifact.

## How changes ship

```mermaid
flowchart LR
    pr[Pull request] --> v["Validate<br/>fmt · validate · tfsec"]
    v --> b["Build<br/>one image,<br/>git-SHA tagged"]
    b --> d["Deploy DEV<br/>auto + smoke test"]
    d --> pp["Plan PROD"]
    pp --> gate{{"Manual approval"}}
    gate --> ap["Apply PROD<br/>+ smoke test"]
```

One image per commit, tagged with the full git SHA. Dev deploys ungated (fast feedback is dev's purpose); the human gate guards *promotion*. Prod applies the exact plan file reviewed at the gate. After every apply, the pipeline smoke-tests its own deployment — polling `/health` with retries budgeted for scale-from-zero cold starts, and failing the run unless the app answers healthy, with the deployed SHA, from the correct environment.

![The promotion gate](images/promotion-gate-approval.png)

## The zero-secrets design

**Every access is an identity with a least-privilege role.** The app's user-assigned managed identity holds exactly three rights: `AcrPull` on the registry, `Key Vault Secrets User` on its own environment's vault, `Storage Blob Data Contributor` on its own environment's storage. Nothing else, nowhere else.

**Nothing is stealable.** The identity has no password — Azure mints it short-lived tokens via the metadata service, inside the running container. There is no connection string in an environment variable to exfiltrate, no key in Terraform state, nothing to phish. The classic breach scenario — stolen credential replayed from an attacker's machine — has no credential to power it.

**Credential paths are closed, not just unused.** Registry admin access is disabled; storage shared-key auth is disabled (`shared_access_key_enabled = false`). Verified from the outside: `az acr credential show` errors, key-based storage requests 403 — while both environments run.

**Why a user-assigned identity (not system-assigned):** a system-assigned identity exists only *after* the app is created — but the app must pull its image *with* that identity, *during* creation. Circular. Creating the identity first, granting `AcrPull`, then creating the app wearing it breaks the loop.

**The security hardening locked out its own tooling — by design.** With shared keys disabled, the Terraform provider's own post-create storage poll (key-based by default) was refused with a 403 by the account it had just created. The fix — `storage_use_azuread = true` in the provider block, plus a data-plane role for the pipeline identity — brought the tooling into compliance with the architecture rather than weakening the architecture for the tooling.

**The trade-off, owned: the pipeline can now administer RBAC.** Creating role assignments requires more than Contributor, so the pipeline's service principal holds *Role Based Access Control Administrator* — an expansion of the Contributor-only doctrine from project #1, made because identities-and-their-rights are now infrastructure this pipeline manages. The mitigation: the role grants RBAC writes and nothing else (unlike Owner), and every assignment it creates is itself reviewed code in this repo.

**Identity is the boundary — the network deliberately isn't.** tfsec flagged the Key Vault's absent network ACL (critical). A Deny-default ACL would block both legitimate clients — the Container App (dynamic egress IPs) and hosted pipeline agents — and the proper fix, VNet integration plus a private endpoint, is precisely the architecture the companion project demonstrates. The finding is deferred with that reasoning annotated inline; reachable is not accessible when every operation demands an Azure AD token from an authorized identity.

## Other design decisions

**Environments are data, not code.** Dev/prod differences (replicas, CPU, the name the app reports) live in committed `dev.tfvars`/`prod.tfvars` — gitignore-excepted deliberately, because these hold environment definitions, not secrets. Adding staging would be a tfvars file and a state key, zero new Terraform.

**Isolated state per environment; blast-radius isolation.** A botched dev apply cannot touch prod — prod isn't in the state being written. The shared registry lives in a third, rarely-touched state, applied manually bootstrap-style.

**SHA tags, never latest.** Every image is tagged with the commit that built it, and the running app reports its tag at `/health` — ask production which commit it is, and it answers.

**Security findings are triaged, not silenced.** tfsec runs at full sensitivity. Phase 4's scan produced five findings: three fixed (TLS floor pinned, secret content-type and expiry added), two deferred with reasoned annotations (network ACL — see above; purge protection, which would lock vault names for 90 days per destroy in an environment that rebuilds routinely). The gate's sensitivity was never lowered.

**Cold-start-literate automation.** Dev scales to zero, so smoke tests retry rather than fail on first wake-up; scripts `set -e` so failures report at their cause.

**Flat configuration, no modules — unlike project #1.** Per-environment parameterization lives in tfvars; three-ish resources per concern don't earn module ceremony. Different project, different structure, both reasoned.

**ASCII-only in code comments.** Learned directly: a Unicode em-dash in a comment made two terraform versions disagree about column alignment — local fmt passed, the pipeline's pinned version failed, on identical content. Multi-byte characters and column-math tooling don't mix.

## Repository structure

```
├── app/
│   ├── main.py              # FastAPI: /health (liveness) + /identity (zero-secrets proof)
│   └── requirements.txt     # fastapi, uvicorn, azure-identity, azure-keyvault-secrets, azure-storage-blob
├── Dockerfile               # Multi-stage, non-root, ~150MB
├── azure-pipelines.yml      # The promotion flow
├── main.tf                  # One environment definition (which one = init key + tfvars)
├── variables.tf
├── outputs.tf
├── dev.tfvars / prod.tfvars # Environment definitions, committed on purpose
├── shared/main.tf           # The registry (own state, manual apply, admin disabled)
├── docs/project-plan.md
└── images/
```

## Local development

```bash
# Local container loop — no Azure needed:
docker build -t container-demo:local .
docker run --rm -p 8000:8000 container-demo:local

# Terraform sessions declare their environment at init AND plan — always together:
terraform init -reconfigure -backend-config="key=container-app-dev.tfstate"
terraform plan -var-file=dev.tfvars
# Prod is pipeline territory; local prod sessions are the exception.
```

## Getting started (from zero)

Prerequisites: Terraform ≥ 1.5, Azure CLI, Docker Desktop, a state storage account, `Microsoft.App` registered, and an Azure DevOps setup (variable group with SP credentials; the SP holding Contributor + RBAC Administrator + AcrPush; a gated `Prod1` environment).

```bash
cd shared && terraform init && terraform apply && cd ..   # the registry, once
# then: merge anything to main — the pipeline builds, deploys dev,
# pauses at the gate, and creates prod on approval.
```

## Cost

Prod's always-warm replica ~$12/month, ACR Basic ~$5, dev scales to zero; Key Vault and storage at demo volume are pennies. ~$17/month as a permanently live demo; set prod's `min_replicas = 0` to idle at ~$5.

## Project status

- [x] **Phase 1 — Containerize + core infrastructure**: multi-stage Dockerfile, ACR, Container Apps via Terraform
- [x] **Phase 2 — CI/CD**: SHA-tagged builds, plan-as-artifact, gated apply, self-verifying smoke tests
- [x] **Phase 3 — Multi-environment promotion**: dev and prod from one configuration; merge → dev → gate → prod
- [x] **Phase 4 — Zero secrets**: managed identity for registry, vault, and storage; credential paths disabled and verified dead
- [ ] **Phase 5 — Observability**: per-environment Log Analytics and a 5xx alert matched to the app's failure contract, verified by fire drill

Full plan: [docs/project-plan.md](docs/project-plan.md)
