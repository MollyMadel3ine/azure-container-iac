"""
Minimal FastAPI service for the container project.

Simpler than project #1's app on purpose: there is no database tier
here. The health endpoint reports container/runtime metadata instead -
which becomes genuinely useful in Phase 3, when two environments run
this same image with different configuration, and /health is how you
tell them apart.

Phase 4 will extend this with managed-identity access to storage and
Key Vault.
"""

import os
import socket
from datetime import datetime, timezone

from fastapi import FastAPI

app = FastAPI(title="container-demo")

# Injected per-environment via Terraform in Phase 3; defaults keep
# local docker runs working with zero configuration.
ENVIRONMENT = os.environ.get("APP_ENVIRONMENT", "local")
IMAGE_TAG = os.environ.get("IMAGE_TAG", "dev")

STARTED_AT = datetime.now(timezone.utc).isoformat()


@app.get("/")
def root():
    return {
        "app": "container-demo",
        "environment": ENVIRONMENT,
        "message": "Containerized IaC demo - view /health",
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "environment": ENVIRONMENT,
        "image_tag": IMAGE_TAG,
        "hostname": socket.gethostname(),  # the container/replica ID
        "started_at": STARTED_AT,
    }
